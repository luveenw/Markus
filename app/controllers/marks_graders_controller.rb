include CsvHelper

# Manages actions relating to assigning graders.
class MarksGradersController < ApplicationController
  include GradersHelper
  # Administrator
  # -
  before_filter      :authorize_only_for_admin

  def upload_dialog
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    render :partial => "graders/modal_dialogs/upload_dialog.rjs"
  end

  def download_dialog
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    render :partial => "graders/modal_dialogs/download_dialog.rjs"
  end

  def groups_coverage_dialog
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @grouping = Grouping.find(params[:grouping])
    render :partial => "graders/modal_dialogs/groups_coverage_dialog.rjs"
  end

  def grader_criteria_dialog
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @grader = Ta.find(params[:grader])
    render :partial => "graders/modal_dialogs/grader_criteria_dialog.rjs"
  end


  def populate
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id],
                                  :include => [{
                                      :groupings => [
                                          :students, :tas,
                                        :group]}])
    @groupings = @grade_entry_form.groupings
    @table_rows = construct_table_rows(@groupings, @grade_entry_form)
  end

  def populate_graders
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @graders = Ta.find(:all)
    @table_rows = construct_grader_table_rows(@graders, @grade_entry_form)
  end

  def populate_criteria
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id],
                                  :include => [
                                    {:rubric_criteria =>
                                        :criterion_ta_associations},
                                    {:flexible_criteria =>
                                        :criterion_ta_associations}])
    @criteria = @grade_entry_form.get_criteria
    @table_rows = construct_criterion_table_rows(@criteria, @grade_entry_form)
  end

  def set_assign_criteria
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    if params[:value] == 'true'
      @grade_entry_form.assign_graders_to_criteria = true
    else
      @grade_entry_form.assign_graders_to_criteria = false
    end
    @grade_entry_form.save
  end

  def index
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
  end

  # Assign TAs to Groupings via a csv file
  def csv_upload_grader_groups_mapping
    if !request.post? || params[:grader_mapping].nil?
      flash[:error] = I18n.t("csv.group_to_grader")
      redirect_to :action => 'index', :grade_entry_form_id => params[:grade_entry_form_id]
      return
    end

    invalid_lines = Grouping.assign_tas_by_csv(params[:grader_mapping].read,
                                               params[:grade_entry_form_id], params[:encoding])
    if invalid_lines.size > 0
      flash[:invalid_lines] = invalid_lines
    end
    redirect_to :action => 'index', :grade_entry_form_id => params[:grade_entry_form_id]
  end

  # Assign TAs to Criteria via a csv file
  def csv_upload_grader_criteria_mapping
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    if !request.post? || params[:grader_criteria_mapping].nil?
      flash[:error] = I18n.t("csv.criteria_to_grader")
      redirect_to :action => 'index', :grade_entry_form_id => params[:grade_entry_form_id]
      return
    end

    if @grade_entry_form.marking_scheme_type == 'rubric'
      invalid_lines = RubricCriterion.assign_tas_by_csv(
      params[:grader_criteria_mapping].read, params[:grade_entry_form_id], params[:encoding])
    else
      invalid_lines = FlexibleCriterion.assign_tas_by_csv(
      params[:grader_criteria_mapping].read, params[:grade_entry_form_id], params[:encoding])
    end
    if invalid_lines.size > 0
      flash[:invalid_lines] = invalid_lines
    end
    redirect_to :action => 'index', :grade_entry_form_id => params[:grade_entry_form_id]
  end

  def download_grader_groupings_mapping
    assignment = GradeEntryForm.find(params[:grade_entry_form_id], :include => [{:groupings => :group}])

    #get all the groups
    groupings = assignment.groupings

    file_out = CsvHelper::Csv.generate do |csv|
       groupings.each do |grouping|
         group_array = [grouping.group.group_name]
         # csv format is group_name, ta1_name, ta2_name, ... etc
         grouping.tas.each do |ta|
            group_array.push(ta.user_name);
         end
         csv << group_array
       end
     end

    send_data(file_out, :type => "text/csv", :disposition => "inline")
  end

  def download_grader_criteria_mapping
    assignment = GradeEntryForm.find(params[:grade_entry_form_id])

    #get all the criteria
    criteria = assignment.get_criteria

    file_out = CsvHelper::Csv.generate do |csv|
       criteria.each do |criterion|
         criterion_array = [criterion.get_name]
         # csv format is criterion_name, ta1_name, ta2_name, ... etc
         criterion.tas.each do |ta|
            criterion_array.push(ta.user_name);
         end
         csv << criterion_array
       end
     end

    send_data(file_out, :type => "text/csv", :disposition => "inline")
  end

  def add_grader_to_grouping
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @grouping = Grouping.find(params[:grouping_id],
                                :include => [:students, :tas, :group])
    grader = Ta.find(params[:grader_id])
    @grouping.add_tas(grader)
    @groupings_data = construct_table_rows([@grouping.reload],@grade_entry_form)
    @graders_data = construct_grader_table_rows([grader], @grade_entry_form)
    criteria = grader.get_criterion_associations_by_assignment(@grade_entry_form).map{|c| c.criterion}
    criteria.each do |criterion|
      criterion.save
    end
    @criteria_data = construct_criterion_table_rows(criteria, @grade_entry_form)
  end

  #These actions act on all currently selected graders & groups
  def global_actions
    grouping_ids = params[:groupings]
    grader_ids = params[:graders]
    criteria_ids = params[:criteria]

    case params[:current_table]
      when "groups_table"
        @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id],
          :include => [{:rubric_criteria => :criterion_ta_associations},
            {:flexible_criteria => :criterion_ta_associations}])
        if params[:groupings].nil? or params[:groupings].size ==  0
         #if there is a global action than there should be a group selected
          if params[:global_actions]
              @global_action_warning = I18n.t("assignment.group.select_a_group")
              render :partial => "shared/global_action_warning.rjs"
              return
          end
        end
        groupings = Grouping.where(:id => grouping_ids).includes(:assignment,
                                                                 :students,
                                                                 {:tas => :criterion_ta_associations},
                                                                 :group)
        case params[:global_actions]
          when "assign"
            if params[:graders].nil? or params[:graders].size ==  0
              @global_action_warning = I18n.t("assignment.group.select_a_grader")
              render :partial => "shared/global_action_warning.rjs"
              return
            end
            add_graders(groupings, grader_ids)
            return
          when "unassign"
            remove_graders(groupings, params)
            return
          when "random_assign"
            if params[:graders].nil? or params[:graders].size ==  0
              @global_action_warning = I18n.t("assignment.group.select_a_grader")
              render :partial => "shared/global_action_warning.rjs"
              return
            end
            randomly_assign_graders(groupings, grader_ids)
            return
        end
      when "criteria_table"
        @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id],
          :include => [{:groupings => [:students,
                {:tas => :criterion_ta_associations}, :group]}])
        if params[:criteria].nil? or params[:criteria].size ==  0
      #don't do anything if no criteria
          render :nothing => true
          return
        end
        if @grade_entry_form.marking_scheme_type == "rubric"
          criteria = RubricCriterion.where(:id => criteria_ids).includes(:criterion_ta_associations)
        else
          criteria = FlexibleCriterion.where(:id => criteria_ids).includes(:criterion_ta_associations)
        end
        case params[:global_actions]
          when "assign"
          if params[:graders].nil? or params[:graders].size ==  0
            #don't do anything if no graders
            render :nothing => true
            return
          end
            graders = Ta.where(:id => grader_ids)
            add_graders_to_criteria(criteria, graders)
            return
          when "unassign"
            remove_graders_from_criteria(criteria, params)
            return
          when "random_assign"
            if params[:graders].nil? or params[:graders].size ==  0
              #don't do anything if no graders
              render :nothing => true
              return
            end
            randomly_assign_graders_to_criteria(criteria, grader_ids)
            return
        end
    end
  end

  private
  #These methods are called through global actions

  def randomly_assign_graders_to_criteria(criteria, grader_ids)
    graders = Ta.where(:id => grader_ids)
    # Shuffle the criteria
    criteria = criteria.sort_by{rand}
    # Now, deal them out like cards...
    criteria.each_with_index do |criterion, index|
      # Choose the next grader to deal out to...
      grader = graders[index % graders.size]
      criterion.add_tas(grader)
      criterion.save
    end
    groupings = []
    graders.each do |grader|
      groupings.concat(grader.get_groupings_by_assignment(@grade_entry_form))
    end
    groupings = groupings.uniq
    construct_all_rows(groupings, graders, criteria)
    render :modify_criteria
  end

  def randomly_assign_graders(groupings, grader_ids)
    graders = Ta.where(:id => grader_ids).includes(:criterion_ta_associations)
    # Shuffle the groupings
    groupings = groupings.sort_by{rand}
    # Now, deal them out like cards...
    groupings.each_with_index do |grouping, index|
      # Choose the next grader to deal out to...
      grader = graders[index % graders.size]
      grouping.add_tas(grader)
    end
    criteria = @grade_entry_form.get_criteria
    criteria.each do |criterion|
      criterion.save
    end
    construct_all_rows(groupings, graders, criteria)
    render :modify_groupings
  end

  def add_graders(groupings, grader_ids)
    graders = Ta.where(:id => grader_ids).includes(:criterion_ta_associations)
    #only want valid graders
    graders = graders.collect {|grader| grader if grader.valid?}
    groupings.each do |grouping|
      grouping.add_tas(graders)
    end
    criteria = @grade_entry_form.get_criteria
    criteria.each do |criterion|
      criterion.save
    end
    construct_all_rows(groupings, graders, criteria)
    render :modify_groupings
  end

  def add_graders_to_criteria(criteria, graders)
    criteria.each do |criterion|
      criterion.add_tas(graders)
      criterion.save
    end
    groupings = []
    graders.each do |grader|
      groupings.concat(grader.get_groupings_by_assignment(@grade_entry_form))
    end
    groupings = groupings.uniq
    groupings.each do |grouping|
      covered_criteria = grouping.all_assigned_criteria(grouping.tas)
      grouping.criteria_coverage_count = covered_criteria.length
      grouping.save
    end
    construct_all_rows(groupings, graders, criteria)
    render :modify_criteria
  end

  def remove_graders_from_criteria(criteria, params)
    all_graders = []
    criteria.each do |criterion|
      graders = criterion.tas.delete_if do |grader|
                  !params["#{criterion.id}_#{grader.user_name}"]
                end
      criterion.remove_tas(graders)
      criterion.save
      all_graders.concat(graders)
    end
    all_graders = all_graders.uniq
    groupings = []
    all_graders.each do |grader|
      groupings.concat(grader.get_groupings_by_assignment(@grade_entry_form))
    end
    groupings = groupings.uniq
    groupings.each do |grouping|
      covered_criteria = grouping.all_assigned_criteria(grouping.tas)
      grouping.criteria_coverage_count = covered_criteria.length
      grouping.save
    end
    construct_all_rows(groupings , all_graders, criteria)
    render :modify_criteria
  end

  # Removes the graders contained in params from the groupings given
  # in groupings.
  # This is meant to be called with the params from global_actions, and for
  # each grader to delete it will have a parameter
  # of the form "groupid_graderid"
  def remove_graders(groupings, params)
    groupings.each do |grouping|
      grader_params = params.find_all{|p| p[0].include?("#{grouping.id}_")}
      if grader_params != []
        members = grouping.tas.delete_if do |grader|
                    !params["#{grouping.id}_#{grader.user_name}"]
        end
        grouping.remove_tas(members.map{|member| member.id})
      end
    end
    criteria = @grade_entry_form.get_criteria
    criteria.each do |criterion|
      criterion.save
    end
    construct_all_rows(groupings, Ta.all, @grade_entry_form.get_criteria)
    render :modify_groupings
  end

  def construct_all_rows(groupings, graders, criteria)
    @groupings_data = construct_table_rows(groupings, @grade_entry_form)
    @graders_data = construct_grader_table_rows(graders, @grade_entry_form)
    if @grade_entry_form.assign_graders_to_criteria
      @criteria_data = construct_criterion_table_rows(criteria, @grade_entry_form)
    end
  end
end
