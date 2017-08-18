require 'eventmachine'
require 'rack'
require 'thin'
require 'faye/websocket'
require 'digest'

$INVALID_COMMAND = "error[error:invalid_command|help:Invalid command.]"
$INVALID_STATE = "error[error:invalid_state|help:Invalid command. Run rescue[] or refresh.]"
$INVALID_STATE = "error[error:invalid_state|help:Your connection has not been initialized. Please reconnect.]"
$CORRUPT_DATA = "error[error:corrupt_data|help:Please only send valid tokens, like this one.]"

$state = {}

$default_state = {
	"state" => :none,
	"user" => "",
	"ship" => {}
}

def parse string
	regex = /^(\w+)\[((.*\:.*)\|?)*\]$/
	result = regex.match(string)
	if result
		returna = {
			"root" => result[1],
			"args" => {}
		}
		result[0][result[1].length+1..-2].split("|").each do |i|
			v = i.split(":")
			returna["args"][v[0]] = v[1]
		end
		return returna
	else
		return false
	end
	#Tokens like root[arg:] and root[arg:something|] unexpectedly do not error this, but may give the return value unexpected properties. If you discover errors in the return value, discard it as invalid and 
end

def build_msg root, args
	cmd = root + "["

	#if args
	#	args.each do |i|
#
#		end
	#end

	cmd = cmd + "]"

	return cmd
end

def get_digest env
	return Digest::MD5.hexdigest "#{env["HTTP_USER_AGENT"]}#{env["REMOTE_ADDR"]}"
end
def get_data env
	return $state[get_digest env]
end

#Official name for root[arg:something|etc:etera] messages are (SF) tokens.

App = lambda do |env|
	if Faye::WebSocket.websocket? env
		ws = Faye::WebSocket.new env, ["wstokens"]

		userstate = {"state" => :no_init}

		ws.on :open do |event|
			#Ready the state

			$state[get_digest env] = $default_state
			userstate = get_data(env)
			ws.send "ready[]"
		end

		ws.on :message do |event|
			parsed = parse event.data
			if parsed
				#Special commads
				if parsed["root"] == "rescue"
					userstate["state"] = :none
					ws.send "done[state:none]"
				#elsif parsed["root"] == 
				else
					#State-specific commands
					case userstate["state"]
					when :none
						case parsed["root"]
						when "start"
							userstate["user"] = parsed["args"]["user"]
							userstate["state"] = :loggedin
							ws.send "done[user:#{userstate["user"]}]"
						else
							ws.send $INVALID_COMMAND
						end
					when :loggedin
						case parsed["root"]
						when ""
						else
							ws.send $INVALID_COMMAND
						end
					when :no_init
						ws.send $UNINITIALIZED
					else
						ws.send $INVALID_STATE
					end
				end
			else
				ws.send $CORRUPT_DATA
			end
		end

		ws.on :close do |event|
			p [:close, event.code, event.reason]
			ws = nil
		end

		ws.rack_response

	else
		[200, {'Content-Type' => 'text/plain'}, ['this is a websocket server']]
	end
end

Faye::WebSocket.load_adapter('thin')
Rack::Handler.get('thin').run(App, :Host => "0.0.0.0")