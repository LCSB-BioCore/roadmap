class PublicPagesController < ApplicationController
  after_action :verify_authorized, except: [:template_index, :plan_index]

  # GET template_index
  # -----------------------------------------------------
  def template_index
    templates = Template.live(Template.families(Org.funder.pluck(:id)).pluck(:dmptemplate_id)).publicly_visible.pluck(:id) <<
    Template.where(is_default: true).valid.published.pluck(:id)
    @templates = Template.includes(:org).where(id: templates.uniq.flatten).valid.published.order(title: :asc).page(1)
  end

  # GET template_export/:id
  # -----------------------------------------------------
  def template_export
    # only export live templates, id passed is dmptemplate_id
    @template = Template.live(params[:id])
    # covers authorization for this action.  Pundit dosent support passing objects into scoped policies
    raise Pundit::NotAuthorizedError unless PublicPagePolicy.new( @template).template_export?
    skip_authorization
    # now with prefetching (if guidance is added, prefetch annottaions/guidance)
    @template = Template.includes(:org, phases: {sections:{questions:[:question_options, :question_format, :annotations]}}).find(@template.id)
    @formatting = Settings::Template::DEFAULT_SETTINGS[:formatting]

    begin
      file_name = @template.title.gsub(/[^a-zA-Z\d\s]/, '').gsub(/ /, "_")
      respond_to do |format|
        format.docx { render docx: 'template_export', filename: "#{file_name}.docx" }
        format.pdf do
          render pdf: file_name,
          margin: @formatting[:margin],
          footer: {
            center:    _('Template created using the %{application_name}. Last modified %{date}') % {application_name: Rails.configuration.branding[:application][:name], date: l(@template.updated_at.to_date, formats: :short)},
            font_size: 8,
            spacing:   (@formatting[:margin][:bottom] / 2) - 4,
            right:     '[page] of [topage]'
          }
        end
      end
    rescue ActiveRecord::RecordInvalid => e  # What scenario is this triggered in? it's common to our export pages
      #send back to public_index page
      redirect_to public_templates_path, alert: _('Unable to download the DMP Template at this time.')
    end

  end

  # GET plan_export/:id
  # -------------------------------------------------------------
  def plan_export
    @plan = Plan.find(params[:id])
    # covers authorization for this action.  Pundit dosent support passing objects into scoped policies
    raise Pundit::NotAuthorizedError unless PublicPagePolicy.new(@plan, current_user).plan_organisationally_exportable? || PublicPagePolicy.new(@plan).plan_export?
    skip_authorization
    # This creates exported_plans with no user.
    # Note for reviewers, The ExportedPlan model actually serves no purpose, except
    # to store preferences for PDF export.  These preferences could be moved into
    # the prefs table for individual users, and a more semsible structure implimented
    # to track the exports & formats(html/pdf/ect) of users.
    @exported_plan = ExportedPlan.new.tap do |ep|
      ep.plan = @plan
      ep.phase_id = @plan.phases.first.id
      ep.format = :pdf
      plan_settings = @plan.settings(:export)

      Settings::Template::DEFAULT_SETTINGS.each do |key, value|
        ep.settings(:export).send("#{key}=", plan_settings.send(key))
      end
    end
    # need to determine which phases to export
    @a_q_ids = Answer.where(plan_id: @plan.id).pluck(:question_id).uniq
    @a_s_ids = Question.where(id: @a_q_ids).pluck(:section_id).uniq
    a_p_ids = Section.where(id: @a_s_ids).pluck(:phase_id).uniq
    @phases = Phase.includes(sections: :questions).where(id: a_p_ids).order(:number)
    # name of owner and any co-owners
    @creator_text = @plan.owner.name(false)
    @plan.roles.administrator.not_creator.each do |role|
      @creator_text += ", " + role.user.name(false)
    end
    # Org name of plan owner
    @affiliation = @plan.owner.org.name
    # set the funder name
    @funder = @plan.template.org.funder? ? @plan.template.org.name : nil
    # set the template name and customizer name if applicable
    @template = @plan.template.title
    @customizer = ""
    cust_questions = @plan.questions.where(modifiable: true).pluck(:id)
    # if the template is customized, and has custom answered questions
    if @plan.template.customization_of.present? && Answer.where(plan_id: @plan.id, question_id: cust_questions).present?
      @customizer = _(" Customised By: ") + @plan.template.org.name
    end


    begin
      @exported_plan.save!
      file_name = @plan.title.gsub(/ /, "_")

      respond_to do |format|
        format.pdf do
          @formatting = @plan.settings(:export).formatting
          render pdf: file_name, show_as_html: params.key?('debug'),
            footer: {
              center:    _('Created using the %{application_name}. Last modified %{date}') % {application_name: Rails.configuration.branding[:application][:name], date: l(@plan.updated_at.to_date, formats: :short)},
              font_size: 8,
              spacing:   (@formatting[:margin][:bottom] / 2) - 12,
              right:     '[page] of [topage]',
            }
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      # send to the public_index page
      redirect_to public_plans_path, alert: _('Unable to download the DMP at this time.')
    end
  end

  # GET /plans_index
  # ------------------------------------------------------------------------------------
  def plan_index
    @plans = Plan.publicly_visible.order(:title => :asc).page(1)
  end
end