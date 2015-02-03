require_relative '../lib/files_for_backup'

RSpec.describe 'FilesForBackup' do
  describe '#remove_excludes' do
    before do
      @files = FilesForBackup.new(nil, ['/Volumes/stuff/Exclude Me', '/Volumes/stuff/Exclude More'])
    end
    it 'should remove excluded files and folders' do
      file_list = ['/Volumes/stuff/hi.txt',
                   '/Volumes/stuff/Exclude Me',
                   '/Volumes/stuff/Exclude Me/bye.txt',
                   '/Volumes/stuff/Exclude More',
                   '/Volumes/stuff/Exclude More/goodbye.txt']
      all_files = @files.remove_excludes(file_list)
      expect(all_files.count).to eq(1)
      expect(all_files.first).to eq('/Volumes/stuff/hi.txt')
    end
  end
end
