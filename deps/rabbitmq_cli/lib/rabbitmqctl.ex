## The contents of this file are subject to the Mozilla Public License
## Version 1.1 (the "License"); you may not use this file except in
## compliance with the License. You may obtain a copy of the License
## at http://www.mozilla.org/MPL/
##
## Software distributed under the License is distributed on an "AS IS"
## basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
## the License for the specific language governing rights and
## limitations under the License.
##
## The Original Code is RabbitMQ.
##
## The Initial Developer of the Original Code is GoPivotal, Inc.
## Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.


defmodule RabbitMQCtl do
  import Parser
  import Helpers
  import ExitCodes

  def main(command) do
    :net_kernel.start([:rabbitmqctl, :shortnames])

    {parsed_cmd, options} = parse(command)

    case Helpers.is_command? parsed_cmd do
      false -> HelpCommand.run |> handle_exit(exit_usage)
      true  -> options
               |> autofill_defaults
               |> run_command(parsed_cmd)
               |> StandardCodes.map_to_standard_code
               |> print_standard_messages(command)
               |> handle_exit
    end
  end

  def autofill_defaults(%{} = options) do
    options
    |> autofill_node
    |> autofill_timeout
  end

  defp autofill_node(%{} = opts), do: Map.merge(%{node: get_rabbit_hostname}, opts)

  defp autofill_timeout(%{} = opts), do: Map.merge(%{timeout: :infinity}, opts)

  defp run_command(_, []), do: HelpCommand.run
  defp run_command(options, [command_name | arguments]) do
    command = Helpers.commands[command_name]
    case invalid_flags(command, options) do
      []      ->  connect_to_rabbitmq(options[:node])
                  execute_command(command, arguments, options)
      result  ->  {:bad_option, result}
    end
  end

  defp execute_command(command, arguments, options) do
    if implements_command_behaviour?(command) do
        command.run(arguments, options)
    else
        IO.puts "Error: #{command} module should implement CommandBehaviour"
        # Exit code?
    end
  end

  defp implements_command_behaviour?(module) do
    [CommandBehaviour] === module.module_info(:attributes)[:behaviour]
  end

  defp print_standard_messages({:badrpc, :nodedown} = result, unparsed_command) do
    {_, options} = parse(unparsed_command)

    IO.puts "Error: unable to connect to node '#{options[:node]}': nodedown"
    result
  end

  defp print_standard_messages({:badrpc, :timeout} = result, unparsed_command) do
    {_, options} = parse(unparsed_command)

    IO.puts "Error: {timeout, #{options[:timeout]}}"
    result
  end

  defp print_standard_messages({:too_many_args, _} = result, [cmd | _] = unparsed_command) do
    IO.puts "Error: too many arguments."
    IO.puts "Given:\n\t#{unparsed_command |> Enum.join(" ")}"
    IO.puts "Usage:\n#{cmd |> HelpCommand.command_usage}"
    result
  end

  defp print_standard_messages({:not_enough_args, _} = result, [cmd | _] = unparsed_command) do
    IO.puts "Error: not enough arguments."
    IO.puts "Given:\n\t#{unparsed_command |> Enum.join(" ")}"
    IO.puts "Usage:\n#{cmd |> HelpCommand.command_usage}"
    result
  end

  defp print_standard_messages({:refused, user, _, _} = result, _) do
    IO.puts "Error: failed to authenticate user \"#{user}\""
    result
  end

  defp print_standard_messages({:bad_option, _} = result, [cmd | _] = unparsed_command) do
    IO.puts "Error: invalid options for this command."
    IO.puts "Given:\n\t#{unparsed_command |> Enum.join(" ")}"
    IO.puts "Usage:\n#{cmd |> HelpCommand.command_usage}"
    result
  end

  defp print_standard_messages(result, _) do
    IO.inspect result
    result
  end


  defp handle_exit({:not_enough_args, _}), do: exit_program(exit_usage)
  defp handle_exit({:too_many_args, _}), do: exit_program(exit_usage)
  defp handle_exit({:bad_option, _}), do: exit_program(exit_usage)
  defp handle_exit({:bad_argument, _}), do: exit_program(exit_dataerr)
  defp handle_exit({:badrpc, :timeout}), do: exit_program(exit_tempfail)
  defp handle_exit({:badrpc, :nodedown}), do: exit_program(exit_unavailable)
  defp handle_exit({:refused, _, _, _}), do: exit_program(exit_dataerr)
  defp handle_exit({:error, _}), do: exit_program(exit_software)
  defp handle_exit(:ok), do: handle_exit(:ok, exit_ok)
  defp handle_exit({:ok, result}), do: handle_exit({:ok, result}, exit_ok)
  defp handle_exit(result) when is_list(result), do: handle_exit({:ok, result}, exit_ok)
  defp handle_exit(:ok, code), do: exit_program(code)
  defp handle_exit({:ok, result}, code) do
    IO.inspect result
    exit_program(code)
  end

  defp command_flags(command) do
    command.flags
    |> Enum.concat(Helpers.global_flags)
    |> MapSet.new
  end

  defp invalid_flags(command, opts) do
    # Why not Map.keys(opts) -- (command.flags ++ Helpers.global_flags)
    opts
    |> Map.keys
    |> Enum.uniq
    |> MapSet.new
    |> MapSet.difference(command_flags(command))
    |> MapSet.to_list
  end

  defp exit_program(code) do
    :net_kernel.stop
    exit({:shutdown, code})
  end
end
