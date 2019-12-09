class IssuesController < ApplicationController
  before_action :set_issue, only: [:show, :edit, :update, :destroy]

  # GET /issues
  # GET /issues.json
  def index
    @issues = Issue.all
  end

  # GET /issues/1
  # GET /issues/1.json
  def show
  end

  # GET /issues/new
  def new
    @issue = Issue.new
    @issue_templates = IssueTemplate.all
  end

  # GET /issues/1/edit
  def edit
    @report_parts = ReportPart.where(type: "IssueGroup")
  end

  # POST /issues
  # POST /issues.json
  def create
    respond_to do |format|
      if params.key?(:issue_template) && (IssueTemplate.exists? params[:issue_template])
        @current_report_setting = current_user.settings.find_by_name('current_report').value
        if Report.exists? @current_report_setting
          current_report = Report.find(@current_report_setting)
          unless current_report.report_parts.empty?
            lastIssueGroup = current_report.report_parts.last
            if lastIssueGroup.type == "IssueGroup"
              issue_clone = Issue.create_from_template(lastIssueGroup, IssueTemplate.find(params[:issue_template]))
              if (client = Client.find(params[:client]))
                issue_clone.clients << client
              end
              format.html { redirect_back fallback_location: root_path, notice: 'Issue was successfully created.' }
            else
              format.html { redirect_to reports_path, alert: 'Last report part is no issue group' }
            end
          else
            format.html { redirect_to reports_path, alert: 'No issue group found in current report. Please create a new one first.' }
          end
        else
          format.html { redirect_to reports_path, alert: 'Current report is not in database.' }
        end
      else
        format.html { redirect_to reports_path, alert: 'Issue template not found.' }
      end
    end
  end

  # PATCH/PUT /issues/1
  # PATCH/PUT /issues/1.json
  def update
    if params[:issue][:screenshot].present?
      screenshot = @issue.screenshots.create
      screenshot.description = params[:issue][:screenshot][:description]
      screenshot.save
      screenshot.image.attach(params[:issue][:screenshot][:image])
    end
    if @issue.update(issue_params)
      respond_with_refresh("Issue was successfully updated.", "success")
    else
      respond_with_notify(@issue.errors, "alert")
    end
  end

  # DELETE /issues/1
  # DELETE /issues/1.json
  def destroy
    @issue.destroy
    respond_with_notify("Issue was successfully destroyed.", "success")
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_issue
      @issue = Issue.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def issue_params
      params.require(:issue).permit(:title, :severity, :description, :customtargets, :rating, :recommendation, :type, :index)
    end

    def screenshot_params
      params.require(:issue).require(:screenshot).permit(:image, :description, :order)
    end

    def respond_with_refresh(message = 'Unknown error', type = 'alert', issue = 0)
      @report_parts = ReportPart.where(type: "IssueGroup")
      respond_to do |format|
        format.html { redirect_to root_path }
        format.js { render 'issues/refresh', locals: { message: message, type: type } }
      end
    end

    def respond_with_notify(message = 'Unknown error', type = 'alert')
      respond_to do |format|
        format.html { redirect_to root_path }
        format.js { render 'pages/notify', locals: { message: message, type: type } }
      end
    end
end
