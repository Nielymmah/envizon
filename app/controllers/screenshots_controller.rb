class ScreenshotsController < ApplicationController
  before_action :set_screenshot, only: %i[edit update destroy]

  # GET /screenshots/1/edit
  def edit; end

  # PATCH/PUT /screenshots/1
  # PATCH/PUT /screenshots/1.json
  def update
    @report_parts = ReportPart.where(type: 'IssueGroup')
    if @screenshot.update(screenshot_params)
      respond_with_refresh('Screenshot was successfully updated.', 'success')
    else
      respond_with_notify(@screenshot.errors, 'alert')
    end
  end

  # DELETE /screenshots/1
  # DELETE /screenshots/1.json
  def destroy
    @report_parts = ReportPart.where(type: 'IssueGroup')
    @screenshot.destroy
    respond_with_refresh('Screenshot was successfully destroyed.', 'success')
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  # def set_issue
  #    @issue = Issue.find(params[:issue])
  # end

  def set_screenshot
    @screenshot = Screenshot.find(params[:id])
  end

  def screenshot_params
    params.require(:screenshot).permit(:description, :order)
  end

  def respond_with_refresh(message = 'Unknown error', type = 'alert')
    @current_report = Report.first_or_create
    @report_parts = @current_report.report_parts
    @report_parts_ig = ReportPart.where(type: 'IssueGroup')
    @message = message
    @type = type
    @issue = @screenshot.report_part
    respond_to do |format|
      format.html { redirect_to root_path }
      format.js { render 'issues/refresh' }
    end
  end
end
