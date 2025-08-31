# require 'net/http'
# require 'json'
#
# class Candidate < ApplicationRecord
#   has_one_attached :resume
#
#   after_initialize :set_defaults
#
#   SKILL_LIST = %w[Python Rails React JavaScript SQL HTML CSS Docker Kubernetes C C++]
#
#   def set_defaults
#     self.skills ||= {}
#   end
#
#   def parse_resume
#     return unless resume.attached?
#
#     text = ""
#     # Open the attached file as a tempfile
#     resume.open(tmpdir: Dir.tmpdir) do |file|
#       reader = PDF::Reader.new(file)  # PDF::Reader accepts path or IO
#       reader.pages.each { |page| text += page.text }
#     end
#
#     # Extract skills
#     self.skills = SKILL_LIST.map do
#       |skill| [skill, text.downcase.include?(skill.downcase) ? 1 : 0]
#     end.to_h
#
#     # Simple experience extraction
#     exp_match = text.match(/(\d+)\s+years? of experience/i)
#     self.experience = exp_match ? exp_match[1].to_i : 0
#   end
#
#   def fetch_github_score
#     return unless github_username.present?
#
#     url = URI("https://api.github.com/users/#{github_username}")
#     response = Net::HTTP.get(url)
#     data = JSON.parse(response) rescue {}
#     public_repos = data["public_repos"].to_i
#     followers = data["followers"].to_i
#     self.github_score = public_repos + followers
#   end
#
#   def calculate_total_score
#     skill_score = skills.values.sum * 10 # each skill = 10 pts
#     exp_score = experience * 5
#     self.total_score = skill_score + exp_score + github_score.to_i
#   end
# end

require 'net/http'
require 'json'
require 'uri'

class Candidate < ApplicationRecord
  has_one_attached :resume

  after_initialize :set_defaults

  SKILL_CATEGORIES = {
    'programming_languages' => %w[Python JavaScript TypeScript Ruby Java C C++ C# PHP Go Rust Swift Kotlin Scala],
    'frameworks' => %w[Rails Django Flask FastAPI Express React Vue Angular Next.js Nuxt.js Spring Laravel Symfony],
    'databases' => %w[MySQL PostgreSQL MongoDB Redis SQLite Oracle Cassandra DynamoDB],
    'cloud_platforms' => %w[AWS Azure GCP Docker Kubernetes Terraform Ansible Jenkins],
    'tools' => %w[Git GitHub GitLab Linux Unix Bash PowerShell Nginx Apache Elasticsearch]
  }.freeze

  def set_defaults
    self.skills ||= {}
    self.experience ||= 0
    self.github_score ||= 0
    self.total_score ||= 0
  end

  def parse_resume_with_ai
    return { success: false, error: "No resume attached" } unless resume.attached?

    begin
      # Extract text from resume
      resume_text = extract_text_from_resume
      return { success: false, error: "Could not extract text from resume" } if resume_text.blank?

      # Use AI to parse resume
      ai_response = analyze_resume_with_ai(resume_text)

      if ai_response[:success]
        update_candidate_from_ai_analysis(ai_response[:data])
        calculate_total_score
        { success: true, message: "Resume parsed successfully with AI" }
      else
        # Fallback to basic parsing if AI fails
        fallback_parse_resume(resume_text)
        { success: true, message: "Resume parsed with fallback method", warning: ai_response[:error] }
      end

    rescue => e
      Rails.logger.error "Resume parsing failed: #{e.message}"
      { success: false, error: "Resume parsing failed: #{e.message}" }
    end
  end

  def extract_text_from_resume
    text = ""

    resume.open(tmpdir: Dir.tmpdir) do |file|
      case resume.content_type
      when 'application/pdf'
        reader = PDF::Reader.new(file)
        reader.pages.each { |page| text += page.text }
      when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        # For DOCX files, you'd need docx gem
        text = extract_docx_text(file)
      when 'text/plain'
        text = file.read
      else
        # Try PDF as default
        reader = PDF::Reader.new(file)
        reader.pages.each { |page| text += page.text }
      end
    end

    text.strip
  end

  def analyze_resume_with_ai(resume_text)
    return { success: false, error: "Gemini API key not configured" } unless ENV['GEMINI_API_KEY']

    prompt = build_analysis_prompt(resume_text)

    begin
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=#{ENV['GEMINI_API_KEY']}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'

      request.body = {
        contents: [
          {
            parts: [
              {
                text: "You are an expert resume parser. Extract information accurately and return valid JSON only.\n\n#{prompt}"
              }
            ]
          }
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 1500,
          responseMimeType: "application/json"
        }
      }.to_json

      response = http.request(request)

      if response.code == '200'
        result = JSON.parse(response.body)
        content = result.dig('candidates', 0, 'content', 'parts', 0, 'text')

        if content
          # Parse the JSON response from AI
          parsed_data = JSON.parse(content)
          { success: true, data: parsed_data }
        else
          { success: false, error: "No content in Gemini response" }
        end
      else
        error_body = JSON.parse(response.body) rescue { 'error' => 'Unknown error' }
        { success: false, error: "Gemini API error: #{response.code} - #{error_body['error']}" }
      end

    rescue JSON::ParserError => e
      { success: false, error: "Failed to parse AI response: #{e.message}" }
    rescue => e
      { success: false, error: "AI analysis failed: #{e.message}" }
    end
  end

  def build_analysis_prompt(resume_text)
    skills_list = SKILL_CATEGORIES.values.flatten.join(', ')

    <<~PROMPT
      Analyze this resume and extract the following information. Return ONLY valid JSON with no additional text:

      {
        "skills": {
          "programming_languages": ["list of found programming languages"],
          "frameworks": ["list of found frameworks"],
          "databases": ["list of found databases"],
          "cloud_platforms": ["list of found cloud/DevOps tools"],
          "tools": ["list of found development tools"]
        },
        "experience_years": number_of_years_of_total_experience,
        "education": {
          "degree": "highest degree",
          "field": "field of study",
          "institution": "university/college name"
        },
        "contact_info": {
          "email": "email_address",
          "phone": "phone_number",
          "linkedin": "linkedin_profile",
          "github": "github_username"
        },
        "work_experience": [
          {
            "company": "company_name",
            "position": "job_title",
            "duration": "employment_duration",
            "description": "brief_role_summary"
          }
        ],
        "certifications": ["list of certifications"],
        "summary": "brief professional summary"
      }

      Available skills to look for: #{skills_list}

      Resume text:
      #{resume_text}
    PROMPT
  end

  def update_candidate_from_ai_analysis(data)
    # Update skills with structured format
    if data['skills']
      structured_skills = {}
      data['skills'].each do |category, skill_list|
        skill_list.each do |skill|
          structured_skills[skill] = 1 if SKILL_CATEGORIES.values.flatten.map(&:downcase).include?(skill.downcase)
        end
      end
      self.skills = structured_skills
    end

    # Update experience
    self.experience = data['experience_years'].to_i if data['experience_years']

    # Update contact information
    if data['contact_info']
      contact = data['contact_info']
      self.email = contact['email'] if contact['email'] && self.email.blank?
      self.phone = contact['phone'] if contact['phone'] && respond_to?(:phone=)
      self.linkedin_url = contact['linkedin'] if contact['linkedin'] && respond_to?(:linkedin_url=)
      self.github_username = extract_github_username(contact['github']) if contact['github']
    end

    # Store additional parsed data in JSON fields (if you have them)
    if respond_to?(:education=)
      self.education = data['education']
    end

    if respond_to?(:work_history=)
      self.work_history = data['work_experience']
    end

    if respond_to?(:certifications=)
      self.certifications = data['certifications']
    end

    if respond_to?(:professional_summary=)
      self.professional_summary = data['summary']
    end
  end

  def fallback_parse_resume(text)
    # Original parsing logic as fallback
    self.skills = SKILL_CATEGORIES.values.flatten.map do |skill|
      [skill, text.downcase.include?(skill.downcase) ? 1 : 0]
    end.to_h.select { |_, v| v == 1 }

    # Extract experience
    exp_match = text.match(/(\d+)\s+(?:years?|yrs?)\s+(?:of\s+)?experience/i)
    self.experience = exp_match ? exp_match[1].to_i : 0

    # Extract email
    email_match = text.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    self.email = email_match[0] if email_match && self.email.blank?

    # Extract GitHub username
    github_match = text.match(/github\.com\/([a-zA-Z0-9\-_]+)/i)
    self.github_username = github_match[1] if github_match
  end

  def extract_github_username(github_input)
    return nil unless github_input

    # Handle full URLs or just usernames
    if github_input.include?('github.com')
      match = github_input.match(/github\.com\/([a-zA-Z0-9\-_]+)/i)
      match ? match[1] : nil
    else
      # Assume it's just the username
      github_input.strip
    end
  end

  def fetch_github_score
    return unless github_username.present?

    begin
      url = URI("https://api.github.com/users/#{github_username}")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.read_timeout = 10

      response = http.get(url.path)

      if response.code == '200'
        data = JSON.parse(response.body)
        public_repos = data["public_repos"].to_i
        followers = data["followers"].to_i

        # More sophisticated GitHub scoring
        self.github_score = calculate_github_score(data)
      else
        Rails.logger.warn "GitHub API error for user #{github_username}: #{response.code}"
        self.github_score = 0
      end

    rescue => e
      Rails.logger.error "Failed to fetch GitHub data: #{e.message}"
      self.github_score = 0
    end
  end

  def calculate_github_score(github_data)
    repos = github_data["public_repos"].to_i
    followers = github_data["followers"].to_i
    following = github_data["following"].to_i

    # More nuanced scoring algorithm
    base_score = repos * 2 + followers * 3

    # Bonus for active users (following others indicates engagement)
    engagement_bonus = following > 0 ? [following / 10, 10].min : 0

    # Cap the maximum GitHub score
    [base_score + engagement_bonus, 200].min
  end

  def calculate_total_score
    # Enhanced scoring algorithm
    skill_score = calculate_skill_score
    exp_score = experience * 8  # Increased weight for experience
    github_bonus = github_score.to_i
    education_bonus = calculate_education_bonus

    self.total_score = skill_score + exp_score + github_bonus + education_bonus
  end

  def calculate_skill_score
    return 0 if skills.blank?

    # Weight skills by category importance
    category_weights = {
      'programming_languages' => 15,
      'frameworks' => 12,
      'databases' => 10,
      'cloud_platforms' => 8,
      'tools' => 5
    }

    total = 0
    skills.each do |skill, present|
      next unless present == 1

      category = find_skill_category(skill)
      weight = category_weights[category] || 5
      total += weight
    end

    total
  end

  def find_skill_category(skill)
    SKILL_CATEGORIES.each do |category, skill_list|
      return category if skill_list.map(&:downcase).include?(skill.downcase)
    end
    'tools' # default category
  end

  def calculate_education_bonus
    return 0 unless respond_to?(:education) && education.present?

    degree = education['degree']&.downcase || ''

    case degree
    when /phd|doctorate/
      30
    when /master|msc|mba|ms/
      20
    when /bachelor|bsc|ba|bs/
      10
    when /associate|diploma/
      5
    else
      0
    end
  end

  def extract_docx_text(file)
    # You'll need to add 'docx' gem to your Gemfile
    # For now, return empty string or implement based on your needs
    ""
  end
end

# Usage example in controller or service:
# result = candidate.parse_resume_with_ai
# if result[:success]
#   candidate.fetch_github_score
#   candidate.save!
# else
#   handle_parsing_error(result[:error])
# end