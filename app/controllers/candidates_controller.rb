# class CandidatesController < ApplicationController
#   before_action :set_candidate, only: [:edit, :update, :destroy]
#
#   def index
#     @candidates = Candidate.order(total_score: :desc)
#   end
#
#   def new
#     @candidate = Candidate.new
#   end
#
#   def create
#     @candidate = Candidate.new(candidate_params)
#     if @candidate.save
#       @candidate.parse_resume
#       @candidate.fetch_github_score
#       @candidate.calculate_total_score
#       @candidate.save
#       redirect_to candidates_path, notice: "Candidate added successfully!"
#     else
#       render :new
#     end
#   end
#
#   def edit
#   end
#
#   def update
#     if @candidate.update(candidate_params)
#       @candidate.parse_resume
#       @candidate.fetch_github_score
#       @candidate.calculate_total_score
#       @candidate.save
#       redirect_to candidates_path, notice: "Candidate updated successfully!"
#     else
#       render :edit
#     end
#   end
#
#   def destroy
#     @candidate.destroy
#     redirect_to candidates_path, notice: "Candidate deleted successfully!"
#   end
#
#   private
#
#   def set_candidate
#     @candidate = Candidate.find(params[:id])
#   end
#
#   def candidate_params
#     params.require(:candidate).permit(:name, :github_username, :resume)
#   end
# end

class CandidatesController < ApplicationController
  before_action :set_candidate, only: [:edit, :update, :destroy]

  def index
    @candidates = Candidate.order(total_score: :desc)
  end

  def new
    @candidate = Candidate.new
  end

  def create
    @candidate = Candidate.new(candidate_params)
    if @candidate.save
      @candidate.parse_resume_with_ai
      @candidate.fetch_github_score
      @candidate.save
      redirect_to candidates_path, notice: "Candidate added successfully!"
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @candidate.update(candidate_params)
      @candidate.parse_resume_with_ai
      @candidate.fetch_github_score
      @candidate.save
      redirect_to candidates_path, notice: "Candidate updated successfully!"
    else
      render :edit
    end
  end

  def destroy
    @candidate.destroy
    redirect_to candidates_path, notice: "Candidate deleted successfully!"
  end

  private

  def set_candidate
    @candidate = Candidate.find(params[:id])
  end

  def candidate_params
    params.require(:candidate).permit(:name, :github_username, :resume)
  end
end