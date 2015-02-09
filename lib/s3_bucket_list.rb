class S3BucketList

  CACHE_DATABASE_PATH = Pathname("s3_bucket_list.cache.db")

  def initialize(s3_client, aws_bucket_name, s3_bucket_list_object_prefix, logger=nil)
    @s3_client = s3_client
    @aws_bucket_name = aws_bucket_name
    @s3_bucket_list_object_prefix = s3_bucket_list_object_prefix
    @logger = logger
  end

  def init_cache
    if CACHE_DATABASE_PATH.exist?
      @db = SQLite3::Database.new CACHE_DATABASE_PATH.to_s
      cache_count = @db.execute("select count(*) from s3_bucket_list").first.first
      @logger.info "#{cache_count} S3 files cached from s3://#{@aws_bucket_name}/#{@s3_bucket_list_object_prefix}"
    else
      @logger.info "Building cache of remote S3 files from s3://#{@aws_bucket_name}/#{@s3_bucket_list_object_prefix}"
      all_s3_objects = list_objects
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
      index = @db.execute("CREATE INDEX file_key_index ON s3_bucket_list (file_key);")

      @logger.info "Inserting #{all_s3_object_count} rows into #{CACHE_DATABASE_PATH}"
      all_s3_objects.each do |file|
        @db.execute("INSERT INTO s3_bucket_list (file_key, last_modified, etag, size, storage_class)
                    VALUES (?, ?, ?, ?, ?)", [file[:file_key], file[:last_modified].tv_sec, file[:etag], file[:size], file[:storage_class]])
      end
      @logger.info "#{all_s3_object_count} rows inserted."
    end
  end

  def remove_cache
    CACHE_DATABASE_PATH.delete
    @logger.info "#{CACHE_DATABASE_PATH} deleted."
  end

  def file(s3_key)
    row_data = nil
    @db.execute("select * from s3_bucket_list where file_key = '#{s3_key}';") do |row|
      row_data = {
        file_key: row[0],
        last_modified: row[1],
        etag: row[2],
        size: row[3],
        storage_class: row[4]
      }
    end
    row_data
  end

  def update_file(s3_key, size, last_modified)
    @db.execute("UPDATE s3_bucket_list SET size = (?), last_modified = (?) where file_key = (?)", [size, last_modified, s3_key])
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
                          etag: file.etag.gsub('"',''),
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
