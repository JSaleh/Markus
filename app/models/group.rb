require File.join(File.dirname(__FILE__),'/../../lib/repo/repository')
# Maintains group information for a given user on a specific assignment
class Group < ActiveRecord::Base
  
  after_create :set_repo_name, :build_repository
  
  has_many :groupings
  has_many :submissions, :through => :groupings
  has_many :student_memberships, :through => :groupings
  has_many :ta_memberships, :class_name => "TAMembership", :through =>
  :groupings
  has_many :assignments, :through => :groupings


  validates_presence_of :group_name
  validates_uniqueness_of :group_name
  validates_length_of :group_name, :maximum => 30, :message => "is too long"
  
  # prefix used for autogenerated group_names
  AUTOGENERATED_PREFIX = "group_"

  # Set repository name in database after a new group is created
  def set_repo_name
    self.repo_name = get_autogenerated_group_name
    self.save(false) # need to save!
  end

  # Returns the repository name for this group
  def repository_name
    return self.repo_name
  end
  
  # Returns an autogenerated name for the group using Group::AUTOGENERATED_PREFIX
  # This only works, after a barebone group record has been created in the database
  def get_autogenerated_group_name
    return Group::AUTOGENERATED_PREFIX + self.id.to_s.rjust(4, "0")
  end
  
  def grouping_for_assignment(aid)
    return groupings.first(:conditions => {:assignment_id => aid})
  end
  
  # Returns true, if and only if the configured repository setup
  # allows for externally accessible repositories, in which case
  # file submissions via the Web interface are not permitted. For
  # now, this works for Subversion repositories only.
  def repository_external_commits_only?
    assignment = assignments.first
    return !assignment.allow_web_submits
  end
  
  # Returns the URL for externally accessible repos
  def repository_external_access_url
    return markus_config_repository_external_base_url + "/" + repository_name
  end
  
  def repository_admin?
    return markus_config_repository_admin?
  end
  
  # Returns configuration for repository
  # configuration (TODO: soon this will be a dynamic thing, i.e. per assignment config)
  def repository_config
    conf = Hash.new
    conf["IS_REPOSITORY_ADMIN"] = self.repository_admin?
    conf["REPOSITORY_PERMISSION_FILE"] = markus_config_repository_permission_file
    conf["REPOSITORY_STORAGE"] = markus_config_repository_storage
    return conf
  end
  
  def build_repository
    # Attempt to build the repository
    begin
      # create repositories and write permissions if and only if we are admin
      if markus_config_repository_admin?
        Repository.get_class(markus_config_repository_type, self.repository_config).create(File.join(markus_config_repository_storage, repository_name))
        # Each admin user will have read and write permissions on each repo
        user_permissions = {}
        Admin.all.each do |admin|
          user_permissions[admin.user_name] = Repository::Permission::READ_WRITE
        end
        # Each grader will have read and write permissions on each repo
        Ta.all.each do |ta|
          user_permissions[ta.user_name] = Repository::Permission::READ_WRITE
        end
        group_repo = Repository.get_class(markus_config_repository_type, self.repository_config)
        group_repo.set_bulk_permissions(File.join(markus_config_repository_storage, self.repository_name), user_permissions)
      else
        raise "Cannot build repositories, MarkUs not in authoritative mode!"
      end
    rescue Exception => e
      raise e
    end
    return true
  end
  
  # Return a repository object, if possible
  def repo
    repo_loc = File.join(markus_config_repository_storage, self.repository_name)
    if Repository.get_class(markus_config_repository_type, self.repository_config).repository_exists?(repo_loc)
      return Repository.get_class(markus_config_repository_type, self.repository_config).open(repo_loc)
    else
      raise "Repository not found and MarkUs not in authoritative mode!" # repository not found, and we are not repo-admin
    end
  end

  #Yields a repository object, if possible, and closes it after it is finished
  def access_repo
    repository = self.repo
    yield repository
    repository.close()
  end
end
