require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/partial'
require 'google/apis/sheets_v4'
require 'signet/oauth_2/client'
require 'dotenv/load'
require 'active_support/time'
require 'sass'

set :partial_template_engine, :erb
enable :partial_underscores

before '/api/*' do
	content_type 'application/json'
	check_passphrase
end

before do
	drive_setup
end

get '/styles.css' do
	scss :styles
end

get '/' do 
	@used = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Used').values
	# @by_day = @used.group_by{|u| u[1].to_date}
	@by_day = @used.group_by{|u| u[1].to_date}.sort_by(&:first).reverse
	erb :index
end

post '/api/queue' do
	name = params[:name]
	response = check_used_and_queued(name)
	unless response
		response = add_name_to_queue(name)
		rebuild_queue
	end
	response.to_json
end

post '/api/use' do
	name = params[:name]
	by = params[:by] || 'cb'
	response = check_used(name)
	unless response
		response = add_name_to_used(name, by)
		clear_name_from_queue(name)
		rebuild_queue
	end
	response.to_json
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
# 	response = clear_name_from_queue(params[:name])
# end

# get '/api/rebuild' do
# 	# Rebuild the queue, sorting and ignoring blank rows
# 	response = rebuild_queue.to_json
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
	if used
		used_names = used.map{|u| comparable(u[0])}
		used_index = used_names.index comparable(name)
		if used_index
			response = "OOPS: '#{name}' already Used at #{used[used_index][1]}."
		else
			response = nil
		end
	else
		response = nil
	end
end

def check_used_and_queued(name)
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue!A:A').values.flatten
	response = check_used(name)
	unless response
		queued_names = queue.map{|q| comparable(q)}
		queue_index = queued_names.index comparable(name)
		if queue_index
			response = "OOPS: '#{name}' is already Queued."
		else
			response = nil
		end
	end
	response
end

def add_name_to_queue(name)
	value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[name, timestamp]])
	result = @drive.append_spreadsheet_value(ENV['SHEET_ID'], 'Queue', value_range, value_input_option: 'RAW')
	response = "OK: '#{name}'' added to Queue."
end

def add_name_to_used(name, by)
	value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[name, timestamp, by]])
	result = @drive.append_spreadsheet_value(ENV['SHEET_ID'], 'Used!A:C', value_range, value_input_option: 'RAW')
	response = "OK: '#{name}' Used by '#{by}' at #{timestamp}."
end

def clear_name_from_queue(name)
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue!A:A').values.flatten
	queued_names = queue.map{|q| comparable(q)}
	queue_index = queued_names.index comparable(name)
	if queue_index
		row = queue_index + 1
		range = "Queue!A#{row}:B#{row}"
		value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: [['','']])
		result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
		response = "#{name} cleared from Queue row #{row}."
	else
		response = "#{name} not found in Queue."
	end
end

def rebuild_queue
	# queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values.flatten
	queue = @drive.get_spreadsheet_values(ENV['SHEET_ID'], 'Queue').values
	sorted_queue = queue.reject(&:empty?).sort_by{|q| comparable(q[0])}.map{|q| [q[0], (q[1] || '')]}

	range = "Queue!A:B" # Column A & B
	value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: sorted_queue)
	result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
	
	if sorted_queue.size < queue.size
		# Add blanks for any rows that had blanks
		rows = (0..queue.size).to_a - (0..sorted_queue.size).to_a
		range = "Queue!A#{rows.first}:B#{rows.last}"
		value_range = Google::Apis::SheetsV4::ValueRange.new(range: range, values: [['','']])
		result = @drive.update_spreadsheet_value(ENV['SHEET_ID'], range, value_range, value_input_option: 'RAW')
	end
end

def comparable(text)
	# lower the case and kill spaces
	text.downcase.gsub(' ','') if text
end

def timestamp
	Time.now.in_time_zone('US/Mountain').strftime("%a %b %e %Y %l:%M %p")
end

def display_date(date)
	date.strftime("%a %b %e %Y")
end

def check_passphrase
	unless params[:passphrase] && params[:passphrase] == ENV['PASSPHRASE']
		halt 401, {'Content-Type' => 'application/json'}, 'bad passphrase, sorry'
	end
end
