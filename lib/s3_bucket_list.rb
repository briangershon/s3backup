class S3BucketList
  def initialize(s3_client, aws_bucket_name, s3_bucket_list_object_prefix, logger=nil)
    @s3_client = s3_client
    @aws_bucket_name = aws_bucket_name
    @s3_bucket_list_object_prefix = s3_bucket_list_object_prefix
    @logger = logger
  end

  def list_objects
    all_objects = []
    file_count = 0
    page_count = 1

    @logger.debug "Retrieving first page of bucket listing." unless @logger.nil?
    page = @s3_client.list_objects(
      bucket: @aws_bucket_name,
      prefix: @s3_bucket_list_object_prefix
      )

    page.each do |page|
      page.contents.each do |file|
        all_objects.push({file_key: file.key,
                          last_modified: file.last_modified,
                          etag: file.etag,
                          size: file.size,
                          storage_class: file.storage_class
                          })
        file_count += 1
      end
      page_count += 1
      @logger.debug "Retrieving page #{page_count} of bucket listing. #{file_count} total files thus far." unless @logger.nil?
    end
    all_objects
  end
end
