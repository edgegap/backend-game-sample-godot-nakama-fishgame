extends Node

func find_unique_name(parent: Node, prefix: String = '') -> String:
	var name: String
	while true:
		name = random_name(prefix)
		if not parent.has_node(name):
			break
	return name

func random_name(prefix: String) -> String:
	return prefix + str(randi())

# Command-line settings, passed after "--" (e.g. "-- --server --port=7777").
func has_arg(arg_name: String) -> bool:
	return ("--" + arg_name) in OS.get_cmdline_user_args()

# Returns "--name=value" from the command line, else the environment variable,
# else the default.
func get_setting(arg_name: String, env_name: String = '', default: String = '') -> String:
	var prefix := "--" + arg_name + "="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	if env_name != '' and OS.has_environment(env_name):
		return OS.get_environment(env_name)
	return default
