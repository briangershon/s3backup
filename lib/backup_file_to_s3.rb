require 'aws-sdk-core'
require 'sqlite3'
require 'filesize'

class BackupFileToS3
  def initialize(s3_client=nil, aws_bucket=nil, s3_bucket_list=nil, logger=nil)
    @s3_client = s3_client
    @aws_bucket = aws_bucket
    @s3_cache = s3_bucket_list
    @logger = logger
  end

  def file_needs_upload?(file_path, s3_key)
    local_file_size = file_path.size
    local_file_modified_time = file_path.mtime.tv_sec

    if @s3_cache.nil?
      return true
    end

    remote_file = @s3_cache.file(s3_key)
    if remote_file.nil?
      return true
    else
      s3_file_size = remote_file[:size]
      s3_file_modified_time = remote_file[:last_modified]
      if local_file_size != s3_file_size || local_file_modified_time > s3_file_modified_time
        return true
      else
        return false
      end
    end
  end

  def upload_file(file_path, s3_key)
    file_size = Filesize.from(file_path.size.to_s + " B").pretty
    @logger.info "Uploading #{file_path.basename} (#{file_size}) to #{s3_key}." unless @logger.nil?
    file_open = File.read(file_path)
    @s3_client.put_object(body: file_open, bucket: @aws_bucket, key: s3_key, metadata: { "modified-date" => file_path.mtime.tv_sec.to_s })

    resp = @s3_client.head_object(bucket: @aws_bucket, key: s3_key)
    s3_file_size = resp.content_length
    s3_file_modified_time = resp.last_modified
    @s3_cache.update_file(s3_key, s3_file_size, s3_file_modified_time.tv_sec)

    @logger.info "#{file_path.basename} complete." unless @logger.nil?
  end
end
