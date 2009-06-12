class Assignment < ActiveRecord::Base
  
  has_many :rubric_criteria, :class_name => "RubricCriterion", :order => :position
  has_many :assignment_files
  has_one  :submission_rule 
  has_many :annotation_categories
  
  has_many :groupings
  
  #TODO:  Do we want these Memberships associated to Assignment?
  has_many :ta_memberships, :through => :groupings
  has_many :student_memberships, :through => :groupings
  
  has_many :submissions, :through => :groupings
  has_many :groups, :through => :groupings
  
  validates_associated :assignment_files
  
  validates_presence_of     :repository_folder
  validates_presence_of     :name, :group_min
  validates_uniqueness_of   :name, :case_sensitive => true
  
  validates_numericality_of :group_min, :only_integer => true,  :greater_than => 0
  validates_numericality_of :group_max, :only_integer => true

 

  def validate
    if (group_max && group_min) && group_max < group_min
      errors.add(:group_max, "must be greater than the minimum number of groups")
    end
  end
  
  
  # Returns a Submission instance for this user depending on whether this 
  # assignment is a group or individual assignment
  def submission_by(user) #FIXME: needs schema updates

    # submission owner is either an individual (user) or a group
    owner = self.group_assignment? ? self.group_by(user.id) : user
    return nil unless owner
    
    # create a new submission for the owner 
    # linked to this assignment, if it doesn't exist yet

    # submission = owner.submissions.find_or_initialize_by_assignment_id(id)
    # submission.save if submission.new_record?
    # return submission
    
    
    assignment_groupings = user.active_groupings.delete_if {|grouping| 
      grouping.assignment.id != self.id
    } 
    
    unless assignment_groupings.empty?
      return assignment_groupings.first.submissions.first
    else
      return nil
    end
  end
  
  
  # Return true if this is a group assignment; false otherwise
  def group_assignment?
    group_min != 1 || group_max > 1
  end
  
  # Returns the group by the user for this assignment. If pending=true, 
  # it will return the group that the user has a pending invitation to.
  # Returns nil if user does not have a group for this assignment, or if it is 
  # not a group assignment
  def group_by(uid, pending=false)
    return nil unless group_assignment?
    
    # condition = "memberships.user_id = ?"
    # condition += " and memberships.status != 'rejected'"
    # add non-pending status clause to condition
    # condition += " and memberships.status != 'pending'" unless pending
    # groupings.find(:first, :include => :memberships, :conditions => [condition, uid]) #FIXME: needs schema update
    
    #FIXME: needs to be rewritten using a proper query...
    return User.find(uid).accepted_grouping_for(self.id)    
    
  end
  
  
  # TODO DEPRECATED: use group_assignment? instead
  # Checks if an assignment is an individually-submitted assignment (no groups)
  def individual?
    group_min == 1 && group_max == 1  
  end
  
  # Returns true if a student is allowed to form groups and still allowed to 
  # invite; otherwise, returns false
  def can_invite?
    result = student_form_groups && student_invite_until.getlocal > Time.now
    return result
  end

  def total_mark
    criteria = RubricCriterion.find_all_by_assignment_id(id)
    total = 0
    criteria.each do |criterion|
      total = total + criterion.weight*4
    end
    return total
  end
  
  def has_dependency?
    return !assignment_dependency_id.nil?
  end


  # Create all the groupings for an assignment where students don't work
  # in groups.
  def create_groupings_when_students_work_alone
     @students = Student.find(:all)
     for @student in @students do
        @student.create_group_for_working_alone_student(self.id)
     end
  end
  
  # Clones the Groupings from the assignment with id assignment_id
  # into self.
  def clone_groupings_from(assignment_id)
    original_assignment = Assignment.find(assignment_id)
    self.group_min = original_assignment.group_min
    self.group_max = original_assignment.group_max
    self.student_form_groups = original_assignment.student_form_groups
    self.group_name_autogenerated = original_assignment.group_name_autogenerated
    self.group_name_displayed = original_assignment.group_name_displayed
    original_assignment.groupings.each do |g|
      #create the groupings
      grouping = Grouping.new
      grouping.assignment_id = self.id
      grouping.group_id = g.group_id
      grouping.save
      #create the memberships
      memberships = g.memberships
      memberships.each do |m|
        membership = Membership.new
        membership.user_id = m.user_id
        membership.grouping_id = grouping.id
        membership.type = m.type
        membership.membership_status = m.membership_status
        membership.save
      end
    end
  end
  
end