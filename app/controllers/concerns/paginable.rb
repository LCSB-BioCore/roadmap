module Paginable
  extend ActiveSupport::Concern
  
  included do
    # Renders paginable layout with the partial view passed
    # partial {String} - Represents a path to where the partial view is stored
    # controller {String} - Represents the name of the controller to handles the pagination
    # action {String} - Represents the method name within the controller
    # scope {ActiveRecord::Relation} - Represents scope variable
    # locals {Hash} - A hash objects with any additional local variables to be passed to the partial view
    def paginable_renderise(partial: nil, controller: params[:controller], action: params[:action], scope: nil, locals: {})
      raise ArgumentError, 'scope should be an instance of ActiveRecord::Relation class' unless scope.is_a?(ActiveRecord::Relation)
      raise ArgumentError, 'locals should be an instance of Hash' unless locals.is_a?(Hash)
      @paginable_controller = controller
      @paginable_action = action
      refined_scope = refine_query(scope)
      render(layout: '/layouts/paginable', partial: partial, locals: { 
        controller: controller,
        action: action,
        paginable: refined_scope.respond_to?(:total_pages), 
        scope: refined_scope }.merge(locals))
    end
    # Generates an URL to sort given a sort field.
    # sort_field {String} - Represents the column name for a table
    def paginable_sort_url(sort_field)
      return link_to(sort_link_name(sort_field), sort_link_url(sort_field), 'data-remote': true)
    end
  end
  private
    # Returns the upcase string (e.g ASC or DESC) if sort_direction param is present in any of the forms 'asc', 'desc', 'ASC', 'DESC'
    # otherwise returns nil
    def sort_direction
      if params.present? && params[:sort_direction].present?
        directions = ['asc', 'desc', 'ASC', 'DESC']
        return directions.include?(params[:sort_direction]) ? params[:sort_direction].upcase : 'ASC'
      end
      return nil
    end
    # Returns DESC when ASC is passed and vice versa, otherwise nil
    def swap_sort_direction(direction)
      return 'DESC' if direction == 'ASC'
      return 'ASC' if direction == 'DESC'
    end
    # Refine a scope passed to this concern if any of the params (search, sort_field or page) are present
    def refine_query(scope)
      if params.present?
        scope = scope.search(params[:search]) if params[:search].present? # Can raise NoMethodError if the scope does not define a search method
        if params[:sort_field].present?
          direction = sort_direction
          scope = direction.present? ? scope.order("#{params[:sort_field]} #{direction}") : scope.order("#{params[:sort_field]}") # Can raise ActiveRecord::StatementInvalid (e.g. column does not exist, ambiguity on column, etc)
        end
        if params[:page] == 'ALL'
          scope = scope.page(1) if params[:search].present? || params[:sort_field].present? # Paginate the scope if search or sort_field query params are present
        else
          scope = scope.page(params[:page]) # Can raise error if page is not a number
        end
      end
      return scope
    end
    # Returns the sort link name for a given sort_field. The link name includes html prevented of being escaped
    def sort_link_name(sort_field)
      className = 'fa-sort'
      direction = sort_direction
      if direction.present? && params[:sort_field] == sort_field
        className = direction == 'ASC'? 'fa-sort-asc' : 'fa-sort-desc'
      end
      return raw("<i class=\"fa #{className}\" aria-hidden=\"true\"></i>")
    end
    # Returns the sort url for a given sort_field.
    def sort_link_url(sort_field)
      url = "#{url_for(controller: @paginable_controller || params[:controller], action: @paginable_action || params[:action], page: 'ALL')}?"
      query_string = []
      if params.present?
        query_string << "search=#{params[:search]}" if params[:search].present?
        direction = sort_direction
        if direction.present? && params[:sort_field] == sort_field
          query_string << "sort_direction=#{swap_sort_direction(direction)}"
        else
          query_string << "sort_direction=ASC"
        end 
      end
      query_string << "sort_field=#{sort_field}"
      return url+query_string.join('&') 
    end
end