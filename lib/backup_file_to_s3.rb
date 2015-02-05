require 'aws-sdk-core'
require 'gdbm'
require 'filesize'

class BackupFileToS3
  def initialize(s3_client=nil, aws_bucket=nil, gdbm=nil, logger=nil)
    @s3_client = s3_client
    @aws_bucket = aws_bucket
    @s3_cache = gdbm
    @logger = logger
  end

  def grab_backup_job(s3_key)
    @s3_client.get_object(bucket: @aws_bucket, key: s3_key).body
  end

  def file_needs_upload?(file_path, s3_key)
    local_file_size = file_path.size
    local_file_modified_time = file_path.mtime

    begin
      if has_cached_metadata?(s3_key)
        s3_cache = get_cached_metadata(s3_key)
        s3_file_size = s3_cache['size']
        s3_file_modified_time = Time.at(s3_cache['modified_time'])
      else
        resp = @s3_client.head_object(bucket: @aws_bucket, key: s3_key)
        s3_file_size = resp.content_length
        s3_file_modified_time = resp.last_modified
        update_metadata_cache(file_path, s3_key, s3_file_size, s3_file_modified_time)
      end

      if local_file_size != file_path.size || local_file_modified_time > s3_file_modified_time
        return true
      else
        return false
      end
    rescue Aws::S3::Errors::NotFound
      return true
    end
  end

  def upload_file(file_path, s3_key)
    file_size = Filesize.from(file_path.size.to_s + " B").pretty
    @logger.info "Uploading #{file_path.basename} (#{file_size}) to #{s3_key}." unless @logger.nil?
    file_open = File.read(file_path)
    @s3_client.put_object(body: file_open, bucket: @aws_bucket, key: s3_key, metadata: { "modified-date" => file_path.mtime.tv_sec.to_s })

    # update cache
    resp = @s3_client.head_object(bucket: @aws_bucket, key: s3_key)
    s3_file_size = resp.content_length
    s3_file_modified_time = resp.last_modified
    update_metadata_cache(file_path, s3_key, s3_file_size, s3_file_modified_time)

    @logger.info "#{file_path.basename} complete." unless @logger.nil?
  end

  # caching

  def has_cached_metadata?(s3_key)
    unless s3_key.ascii_only?
      # BUG in GDBM: Value sometimes truncated when data has UTF-8
      @logger.warn "Unable to cache non-ascii data, will retrieve metadata from S3 for #{s3_key}" unless @logger.nil?
      return false
    end
    if @s3_cache
      @s3_cache.has_key?(s3_key)
    else
      false
    end
  end

  def get_cached_metadata(s3_key)
    if @s3_cache
      JSON.parse(@s3_cache[s3_key])
    else
      {}
    end
  end

  def update_metadata_cache(file_path, s3_key, size, last_modified)
    unless s3_key.ascii_only?
      return
    end
    if @s3_cache
      @s3_cache[s3_key] = {
        size: size,
        modified_time: last_modified.tv_sec,
        cached_on: Time.now.tv_sec,
        file_path: file_path,
        s3_key: s3_key,
        bucket: @aws_bucket
      }.to_json
    end
  end
end
