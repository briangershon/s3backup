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

    all_files_minus_excludes = remove_excludes(files_only, logger)

    # convert to Pathname
    all_files = []
    all_files_minus_excludes.each do |file|
      all_files.push(Pathname(file))
    end

    all_files
  end

  def remove_excludes(all_files, logger=nil)
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
