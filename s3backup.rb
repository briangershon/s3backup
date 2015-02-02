#!/usr/bin/env ruby

require 'thor'
require 'aws-sdk-core'
require 'yaml'
require 'pathname'
require_relative 'lib/backup_file_to_s3'
require_relative 'lib/files_for_backup'

def run_backup_job(backup_job_s3_key, aws_bucket, aws_profile)
  @aws_bucket = aws_bucket

  Aws.config[:region] = 'us-east-1'   # this is required but doesn't matter for S3
  Aws.config[:profile] = aws_profile
  s3_client = Aws::S3::Client.new

  s3_cache = GDBM.new("s3_metadata_cache.db")

  @backup_service = BackupFileToS3.new(s3_client, @aws_bucket, s3_cache)
  begin
    backup_job_s3_key = backup_job_s3_key
    puts "Bringing down '#{backup_job_s3_key}' configuration file from S3."
    @backup_job = YAML.load(@backup_service.grab_backup_job(backup_job_s3_key))
  rescue Aws::S3::Errors::NoSuchKey
    puts "Backup Job '#{backup_job_s3_key}' not found. Exiting."
    abort
  end

  @backup_base_path = @backup_job['backup_base_path']
  @backup_folder = @backup_job['backup_folder']
  @backup_folder_excludes = @backup_job['backup_folder_excludes']

  puts "Getting list of local files from #{@backup_folder}."
  @all_files = FilesForBackup.new(@backup_folder, @backup_folder_excludes).files
  files_count = @all_files.count

  puts "#{files_count} files found."
  puts "Backing up to S3://#{@aws_bucket}/#{Pathname(@backup_folder).relative_path_from(Pathname(@backup_base_path))}"

  @all_files.each_with_index do |file, index|
    pn = Pathname.new(file)
    if pn.file?
      key = pn.relative_path_from(Pathname(@backup_base_path))
      if @backup_service.file_needs_upload?(pn, key.to_s)
        @backup_service.upload_file pn, key.to_s
      end
    end
    if index % 100 == 0
      puts "\n#{files_count - index} files left to check."
    end
  end

  s3_cache.close

  puts "\nFinished."
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
