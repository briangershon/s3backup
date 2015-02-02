class FilesForBackup
  def initialize(backup_folder, backup_folder_excludes)
    @backup_folder = backup_folder
    @backup_folder_excludes = backup_folder_excludes
  end

  def files(logger=nil)
    all_files = Dir.glob(@backup_folder)
    @backup_folder_excludes.each do |folder_exclude|
      if Pathname(folder_exclude).exist?
        logger.info "Excluding paths that start with #{folder_exclude}" unless logger.nil?
        all_files.each do |file|
          if file.start_with?(folder_exclude)
            all_files.delete(file)
          end
        end
      else
        logger.error "ALERT: #{folder_exclude} exclude path not found." unless logger.nil?
      end
    end
    all_files
  end
end
