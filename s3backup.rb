#!/usr/bin/env ruby

require 'thor'
require 'aws-sdk-core'
require 'yaml'
require 'pathname'
require 'logger'
require 'sqlite3'
require_relative 'lib/backup_file_to_s3'
require_relative 'lib/files_for_backup'
require_relative 'lib/s3_bucket_list'

LOCAL_FILE_CACHE = Pathname("local_file.cache.db")

def run_backup_job(backup_job_s3_key, aws_bucket, aws_profile)
  @aws_bucket = aws_bucket

  @logger = Logger.new(STDOUT)
  @logger.level = Logger::INFO

  Aws.config[:region] = 'us-east-1'   # this is required but doesn't matter for S3
  Aws.config[:profile] = aws_profile
  s3_client = Aws::S3::Client.new

  @logger.info("Started")
  begin
    backup_job_s3_key = backup_job_s3_key
    @logger.info "Bringing down '#{backup_job_s3_key}' configuration file from S3."
    @backup_job = YAML.load(s3_client.get_object(bucket: @aws_bucket, key: backup_job_s3_key).body)
  rescue Aws::S3::Errors::NoSuchKey
    @logger.error "Backup Job '#{backup_job_s3_key}' not found. Exiting."
    abort
  end

  @backup_base_path = @backup_job['backup_base_path']
  @backup_folder = @backup_job['backup_folder']
  @backup_folder_excludes = @backup_job['backup_folder_excludes']
  @bucket_prefix = Pathname(@backup_folder).relative_path_from(Pathname(@backup_base_path)).to_s

  s3_bucket_list = S3BucketList.new(s3_client, @aws_bucket, @bucket_prefix, @logger)
  s3_bucket_list.init_cache

  @backup_service = BackupFileToS3.new(s3_client, @aws_bucket, s3_bucket_list, @logger)

  all_files_to_backup.each do |file|
    pn = Pathname(file)
    key = pn.relative_path_from(Pathname(@backup_base_path))
    if @backup_service.file_needs_upload?(pn, key.to_s)
      @backup_service.upload_file pn, key.to_s
    end
  end

  remove_local_cache
  s3_bucket_list.remove_cache

  @logger.info "Finished."
  @logger.close
end

def all_files_to_backup
  if LOCAL_FILE_CACHE.exist?
    db = SQLite3::Database.new LOCAL_FILE_CACHE.to_s
    cache_count = db.execute("select count(*) from local_file_list").first.first
    cached_files = db.execute("select * from local_file_list")
    files = []
    cached_files.each do |row|
      file_name = row[0]
      files.push(file_name)
      # row_data = {
      #   file_name: row[0],
      #   file_key: row[1]
      #   last_modified: row[2],
      #   size: row[3]
      # }
      # files.push(row_data)
    end
    @logger.info "Local files cached from #{@backup_folder}: #{cache_count}."
  else
    @logger.info "Creating list of local files from #{@backup_folder}."
    db = SQLite3::Database.new LOCAL_FILE_CACHE.to_s
    rows = db.execute <<-SQL
      create table local_file_list (
        file_path varchar(1024),
        file_key varchar(1024),
        last_modified DATETIME,
        size int
      );
    SQL
    index = db.execute("CREATE INDEX file_path_index ON local_file_list (file_path);")
    index = db.execute("CREATE INDEX file_key_index ON local_file_list (file_key);")

    files = FilesForBackup.new(@backup_folder, @backup_folder_excludes).files(@logger)
    @logger.info "#{files.count} local files found."

    @logger.info "Inserting #{files.count} rows into #{LOCAL_FILE_CACHE}"
    files.each do |file|
      db.execute("INSERT INTO local_file_list (file_path, file_key, last_modified, size)
                  VALUES (?, ?, ?, ?)", [file, Pathname(file).relative_path_from(Pathname(@backup_base_path)).to_s, Pathname(file).mtime.tv_sec, Pathname(file).size])
    end
    @logger.info "#{files.count} rows inserted."
  end

  @logger.info "Backing up to S3://#{@aws_bucket}/#{@bucket_prefix}"
  files
end

def remove_local_cache
  LOCAL_FILE_CACHE.delete
  @logger.info "#{LOCAL_FILE_CACHE} deleted."
end

class BackupToS3 < Thor
  desc "job backup_job_s3_key aws_bucket aws_profile", "run a backup"
  long_desc <<-LONGDESC

  aws_bucket is a string like `my-s3-bucket`

  aws_profile is a profile name in ~/.aws/credentials

  backup_job_s3_key is the name (s3_key) of a YAML file in aws_bucket.

  See README.md for more details.
  LONGDESC
  def job(backup_job_s3_key, aws_bucket, aws_profile)
    run_backup_job(backup_job_s3_key, aws_bucket, aws_profile)
  end
end

BackupToS3.start(ARGV)
