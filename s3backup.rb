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

CACHE_DATABASE_PATH = Pathname("s3_bucket_list.cache.db")

def run_backup_job(backup_job_s3_key, aws_bucket, aws_profile)
  @aws_bucket = aws_bucket

  @logger = Logger.new(STDOUT)
  @logger.level = Logger::INFO

  Aws.config[:region] = 'us-east-1'   # this is required but doesn't matter for S3
  Aws.config[:profile] = aws_profile
  s3_client = Aws::S3::Client.new

  s3_cache = GDBM.new("s3_metadata.cache.db")

  @logger.info("Started")
  @backup_service = BackupFileToS3.new(s3_client, @aws_bucket, s3_cache, @logger)
  begin
    backup_job_s3_key = backup_job_s3_key
    @logger.info "Bringing down '#{backup_job_s3_key}' configuration file from S3."
    @backup_job = YAML.load(@backup_service.grab_backup_job(backup_job_s3_key))
  rescue Aws::S3::Errors::NoSuchKey
    @logger.error "Backup Job '#{backup_job_s3_key}' not found. Exiting."
    abort
  end

  @backup_base_path = @backup_job['backup_base_path']
  @backup_folder = @backup_job['backup_folder']
  @backup_folder_excludes = @backup_job['backup_folder_excludes']
  @bucket_prefix = Pathname(@backup_folder).relative_path_from(Pathname(@backup_base_path)).to_s

  if CACHE_DATABASE_PATH.exist?
    @db = SQLite3::Database.new CACHE_DATABASE_PATH.to_s
    @logger.info "Using cache of remote S3 files from s3://#{@aws_bucket}/#{@bucket_prefix}"
    cache_count = @db.execute("select count(*) from s3_bucket_list").first.first
    @logger.info "Files cached: #{cache_count}"
  else
    @logger.info "Building cache of remote S3 files from s3://#{@aws_bucket}/#{@bucket_prefix}"
    s3_bucket_list = S3BucketList.new(s3_client, @aws_bucket, @bucket_prefix, @logger)
    all_s3_objects = s3_bucket_list.list_objects
    all_s3_object_count = all_s3_objects.count

    @db = SQLite3::Database.new CACHE_DATABASE_PATH.to_s
    rows = @db.execute <<-SQL
      create table s3_bucket_list (
        file_key varchar(1024),
        last_modified DATETIME,
        etag varchar(32),
        size int,
        storage_class varchar(50)
      );
    SQL
    @logger.info "Inserting #{all_s3_object_count} rows into #{CACHE_DATABASE_PATH}"
    all_s3_objects.each do |file|
      @db.execute("INSERT INTO s3_bucket_list (file_key, last_modified, etag, size, storage_class)
                  VALUES (?, ?, ?, ?, ?)", [file[:file_key], file[:last_modified].tv_sec, file[:etag], file[:size], file[:storage_class]])
    end
    @logger.info "#{all_s3_object_count} rows inserted."
  end

  # @db.execute( "select * from s3_bucket_list" ) do |row|
  #   p row
  # end

  @logger.info "Getting list of local files from #{@backup_folder}."
  all_files_cache = Pathname("#{backup_job_s3_key}.cache.json")
  if all_files_cache.exist?
    @all_files = JSON.parse(all_files_cache.read)
    @logger.info "Retrieved cached list of files from '#{all_files_cache}'."
  else
    @all_files = FilesForBackup.new(@backup_folder, @backup_folder_excludes).files(@logger)
    all_files_cache.write(@all_files.to_json)
    @logger.info "Cached list of files to '#{all_files_cache}'."
  end
  files_count = @all_files.count

  @logger.info "#{files_count} files found."
  @logger.info "Backing up to S3://#{@aws_bucket}/#{@bucket_prefix}"

  @all_files.each_with_index do |file, index|
    pn = Pathname(file)
    if pn.file?
      key = pn.relative_path_from(Pathname(@backup_base_path))
      if @backup_service.file_needs_upload?(pn, key.to_s)
        @backup_service.upload_file pn, key.to_s
      end
    end
    if index % 100 == 0
      @logger.debug "#{files_count - index} files left to check."
    end
  end

  s3_cache.close

  all_files_cache.delete
  @logger.info "Deleted '#{all_files_cache}'."

  # CACHE_DATABASE_PATH.delete
  # @logger.info "#{CACHE_DATABASE_PATH} deleted."

  @logger.info "Finished."
  @logger.close
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
