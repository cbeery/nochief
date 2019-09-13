require 'sinatra'
require 'sinatra/reloader' if development?
# require 'sinatra/partial'
require 'google/apis/sheets_v4'
require 'signet/oauth_2/client'
require 'dotenv/load'
# require 'sass'

before do
	drive_setup
end

before '/api/*' do
	content_type 'application/json'
end

get '/' do 
	"We are trying."
end

get '/api/queue' do
	name = params[:name]
	response = check_used_and_queued(name)
	unless response
		response = add_name_to_queue(name)
		rebuild_queue
	end
	response
end

get '/api/use' do
	name = params[:name]
	response = check_used(name)
	unless response
		response = add_name_to_used(name)
		clear_name_from_queue(name)
		rebuild_queue
	end
	response
end

get '/api/check' do
	response = check_used_and_queued(params[:name])
	response.to_json
end

# get '/api/checku' do
# 	response = check_used(params[:name])
# 	response.to_json
# end

# get '/api/clear' do
# 	# Remove a value from the queue
# 	name = params[:name]
# 	response = clear_name_from_queue(name)
# end

# get '/api/rebuild' do
# 	# Rebuild the queue, sorting and ignoring blank rows
# 	response = rebuild_queue.inspect
# end

private

def drive_setup
	auth = Signet::OAuth2::Client.new(
	  token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
	  client_id: 						ENV['GOOGLE_CLIENT_ID'],
	  client_secret: 				ENV['GOOGLE_CLIENT_SECRET'],
	  refresh_token: 				ENV['REFRESH_TOKEN']
	)
	auth.fetch_access_token!
	@drive = Google::Apis::SheetsV4::SheetsService.new
	@drive.authorization = auth
end

def check_used(name)
	used = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Used').values
	used_names = used.map{|u| comparable(u[1])}
	used_index = used_names.index comparable(name)
	if used_index
		response = "#{name} already Used at #{used[used_index][0]}."
	else
		response = nil
	end
end

def check_used_and_queued(name)
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values.flatten.map{|q| comparable(q)}
	response = check_used(name)
	unless response
		queue_index = queue.index comparable(name)
		if queue_index
			response = "#{name} is already Queued."
		else
			response = nil
		end
	end
	response
end

def check_used_and_queued_old(name)
	used = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Used').values
	used_names = used.map{|u| comparable(u[1])}
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values.flatten.map{|q| comparable(q)}
	used_index = used_names.index comparable(name)
	if used_index
		response = "#{name} already Used at #{used[used_index][0]}."
	else
		queue_index = queue.index comparable(name)
		if queue_index
			response = "#{name} is already Queued."
		else
			response = nil
		end
	end
end

def add_name_to_queue(name)
	value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[comparable(name)]])
	result = @drive.append_spreadsheet_value(ENV['SHEET_ID'], 'Queue', value_range, value_input_option: 'RAW')
	response = "#{name} added to Queue."
end

def add_name_to_used(name)
	nice_time = Time.now.strftime("%a %b %e %Y %l:%M %p")
	value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[nice_time, comparable(name)]])
	result = @drive.append_spreadsheet_value(ENV['SHEET_ID'], 'Used', value_range, value_input_option: 'RAW')
	response = "#{name} Used at #{nice_time}."
end

def clear_name_from_queue(name)
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values.flatten
	queue_index = queue.index comparable(name)
	if queue_index
		row = queue_index + 1
		range = "Queue!A#{row}"
		value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: [['']])
		result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
		response = "#{name} cleared from Queue row #{row}."
	else
		response = "#{name} not found in Queue."
	end
end

def rebuild_queue
	# queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values.flatten
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values
	sorted_queue = queue.sort.flatten.map{|s| [s]}

	range = "Queue!A:A" # Column A
	value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: sorted_queue, majorDimension: 'COLUMNS')
	result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
	
	if sorted_queue.size < queue.size
		# Add blanks for any rows that had blanks
		rows = (0..queue.size).to_a - (0..sorted_queue.size).to_a
		range = "Queue!A#{rows.first}:A#{rows.last}"
		value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: [['']])
		result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
	end
end

def comparable(text)
	# lower the case and kill spaces
	text.downcase.gsub(' ','') if text
end
