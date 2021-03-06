module API
  # Projects API
  class Projects < Grape::API
    before { authenticate! }

    resource :projects do
      # Register new webhook for project
      #
      # Parameters
      #   project_id (required) - The ID of a project
      #   web_hook (required) - WebHook URL
      # Example Request
      #   POST /projects/:project_id/webhooks
      post ":project_id/webhooks" do
        required_attributes! [:web_hook]

        project = Project.find(params[:project_id])

        unauthorized! unless current_user.can_manage_project?(project.gitlab_id)
        
        web_hook = project.web_hooks.new({ url: params[:web_hook] })

        if web_hook.save
          present web_hook, with: Entities::WebHook
        else
          errors = web_hook.errors.full_messages.join(", ")
          render_api_error!(errors, 400)
        end
      end

      # Retrieve all Gitlab CI projects that the user has access to
      #
      # Example Request:
      #   GET /projects
      get do
        gitlab_projects = Project.from_gitlab(
          current_user, :authorized, { page: params[:page], per_page: params[:per_page] }
        )
        ids = gitlab_projects.map { |project| project.id }

        projects = Project.where("gitlab_id IN (?)", ids).load
        present projects, with: Entities::Project
      end

      # Retrieve all Gitlab CI projects that the user owns
      #
      # Example Request:
      #   GET /projects/owned
      get "owned" do
        gitlab_projects = Project.from_gitlab(
          current_user, :owned, { page: params[:page], per_page: params[:per_page] }
        )
        ids = gitlab_projects.map { |project| project.id }

        projects = Project.where("gitlab_id IN (?)", ids).load
        present projects, with: Entities::Project
      end

      # Retrieve info for a Gitlab CI project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   GET /projects/:id
      get ":id" do
        project = Project.find(params[:id])

        unauthorized! unless current_user.can_access_project?(project.gitlab_id)

        present project, with: Entities::Project
      end

      # Create Gitlab CI project using Gitlab project info
      #
      # Parameters:
      #   name (required)            - The name of the project
      #   gitlab_id (required)       - The gitlab id of the project
      #   path (required)            - The gitlab project path, ex. randx/six
      #   ssh_url_to_repo (required) - The gitlab ssh url to the repo
      #   default_ref                - The branch to run against (defaults to `master`)
      # Example Request:
      #   POST /projects
      post do
        required_attributes! [:name, :gitlab_id, :gitlab_url, :ssh_url_to_repo]

        filtered_params = {
          name:            params[:name],
          gitlab_id:       params[:gitlab_id],
          # we accept gitlab_url for backward compatibility for a while (added to 7.11)
          path:            params[:post] || params[:gitlab_url].sub(/.*\/(.*\/.*)$/, '\1'),
          default_ref:     params[:default_ref] || 'master',
          ssh_url_to_repo: params[:ssh_url_to_repo]
        }

        project = Project.new(filtered_params)
        project.build_missing_services

        if project.save
          present project, with: Entities::Project
        else
          errors = project.errors.full_messages.join(", ")
          render_api_error!(errors, 400)
        end
      end

      # Update a Gitlab CI project
      #
      # Parameters:
      #   id (required)   - The ID of a project
      #   name            - The name of the project
      #   gitlab_id       - The gitlab id of the project
      #   path            - The gitlab project path, ex. randx/six
      #   ssh_url_to_repo - The gitlab ssh url to the repo
      #   default_ref     - The branch to run against (defaults to `master`)
      # Example Request:
      #   PUT /projects/:id
      put ":id" do
        project = Project.find(params[:id])

        unauthorized! unless current_user.can_manage_project?(project.gitlab_id)

        attrs = attributes_for_keys [:name, :gitlab_id, :path, :gitlab_url, :default_ref, :ssh_url_to_repo]

        # we accept gitlab_url for backward compatibility for a while (added to 7.11)
        if attrs[:gitlab_url] && !attrs[:path]
          attrs[:path] = attrs[:gitlab_url].sub(/.*\/(.*\/.*)$/, '\1')
        end

        if project.update_attributes(attrs)
          present project, with: Entities::Project
        else
          errors = project.errors.full_messages.join(", ")
          render_api_error!(errors, 400)
        end
      end

      # Remove a Gitlab CI project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   DELETE /projects/:id
      delete ":id" do
        project = Project.find(params[:id])

        unauthorized! unless current_user.can_manage_project?(project.gitlab_id)

        project.destroy
      end

      # Link a Gitlab CI project to a runner
      #
      # Parameters:
      #   id (required) - The ID of a CI project
      #   runner_id (required) - The ID of a runner
      # Example Request:
      #   POST /projects/:id/runners/:runner_id
      post ":id/runners/:runner_id" do
        project = Project.find(params[:id])
        runner  = Runner.find(params[:runner_id])

        unauthorized! unless current_user.can_manage_project?(project.gitlab_id)

        options = {
          project_id: project.id,
          runner_id:  runner.id
        }

        runner_project = RunnerProject.new(options)

        if runner_project.save
          present runner_project, with: Entities::RunnerProject
        else
          errors = project.errors.full_messages.join(", ")
          render_api_error!(errors, 400)
        end
      end

      # Remove a Gitlab CI project from a runner
      #
      # Parameters:
      #   id (required) - The ID of a CI project
      #   runner_id (required) - The ID of a runner
      # Example Request:
      #   DELETE /projects/:id/runners/:runner_id
      delete ":id/runners/:runner_id" do
        project = Project.find(params[:id])
        runner  = Runner.find(params[:runner_id])

        unauthorized! unless current_user.can_manage_project?(project.gitlab_id)

        options = {
          project_id: project.id,
          runner_id:  runner.id
        }

        runner_project = RunnerProject.find_by(options)

        if runner_project.present?
          runner_project.destroy
        else
          not_found!
        end
      end
    end
  end
end
