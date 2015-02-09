require 'find'

class FilesForBackup
  def initialize(backup_folder, backup_folder_excludes)
    @backup_folder = backup_folder
    @backup_folder_excludes = backup_folder_excludes
  end

  def files(logger=nil)
    # warn if some folder doesn't exist
    @backup_folder_excludes.each do |folder_exclude|
      unless Pathname(folder_exclude).exist?
        logger.error "ALERT: #{folder_exclude} exclude path not found." unless logger.nil?
      end
    end

    # exclude directories
    find_files = Find.find(@backup_folder).to_a
    files_only = []
    find_files.each do |file|
      if Pathname(file).file?
        files_only.push(file)
      end
    end

    remove_excludes(files_only, logger)
  end

  def remove_excludes(all_files, logger=nil)
    logger.info "Excluding paths..." unless logger.nil?
    new_file_list = []
    all_files.each do |file|
      exclude = false
      @backup_folder_excludes.each do |folder_exclude|
        if file.start_with?(folder_exclude)
          exclude = true
          break
        end
      end
      unless exclude
        new_file_list.push(file)
      end
    end
    new_file_list
  end
end
