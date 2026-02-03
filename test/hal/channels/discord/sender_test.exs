defmodule Hal.Channels.Discord.SenderTest do
  use ExUnit.Case, async: true

  alias Hal.Channels.Discord.Sender

  describe "build_message_opts/1" do
    test "returns content for simple text message" do
      opts = Sender.build_message_opts("Hello, World!")

      assert opts == [content: "Hello, World!"]
    end

    test "handles message with reply reference" do
      opts = Sender.build_message_opts("Response text", reply_to: 123_456)

      assert opts[:content] == "Response text"
      assert opts[:message_reference] == %{message_id: 123_456}
    end

    test "handles message with embed" do
      embed = %{
        title: "Test Embed",
        description: "A test embed",
        color: 0x00FF00
      }

      opts = Sender.build_message_opts("", embed: embed)

      assert opts[:embeds] == [embed]
    end

    test "handles message with file attachment" do
      file_path = "/path/to/file.txt"
      opts = Sender.build_message_opts("Here's a file", file: file_path)

      assert opts[:content] == "Here's a file"
      assert opts[:file] == file_path
    end
  end

  describe "chunk_message/2" do
    test "returns single chunk for short message" do
      short_msg = "This is a short message"
      chunks = Sender.chunk_message(short_msg)

      assert chunks == [short_msg]
    end

    test "splits long message at 2000 chars (Discord limit)" do
      long_msg = String.duplicate("a", 2500)
      chunks = Sender.chunk_message(long_msg)

      assert length(chunks) == 2
      assert String.length(Enum.at(chunks, 0)) <= 2000
      assert String.length(Enum.at(chunks, 1)) <= 2000
    end

    test "preserves message content when chunking" do
      long_msg = String.duplicate("x", 3000)
      chunks = Sender.chunk_message(long_msg)

      joined = Enum.join(chunks, "")
      assert joined == long_msg
    end

    test "respects custom max length" do
      msg = String.duplicate("b", 150)
      chunks = Sender.chunk_message(msg, max_length: 50)

      assert length(chunks) == 3

      Enum.each(chunks, fn chunk ->
        assert String.length(chunk) <= 50
      end)
    end
  end

  describe "format_code_block/2" do
    test "wraps content in code block" do
      code = "def hello, do: :world"
      result = Sender.format_code_block(code)

      assert result == "```\ndef hello, do: :world\n```"
    end

    test "adds language hint when specified" do
      code = "def hello, do: :world"
      result = Sender.format_code_block(code, "elixir")

      assert result == "```elixir\ndef hello, do: :world\n```"
    end
  end

  describe "build_embed/1" do
    test "creates embed with title and description" do
      embed =
        Sender.build_embed(
          title: "Test Title",
          description: "Test description"
        )

      assert embed.title == "Test Title"
      assert embed.description == "Test description"
    end

    test "creates embed with color" do
      embed =
        Sender.build_embed(
          title: "Colored",
          color: :success
        )

      assert embed.color == 0x57F287
    end

    test "creates embed with error color" do
      embed =
        Sender.build_embed(
          title: "Error",
          color: :error
        )

      assert embed.color == 0xED4245
    end

    test "creates embed with fields" do
      embed =
        Sender.build_embed(
          title: "With Fields",
          fields: [
            %{name: "Field 1", value: "Value 1"},
            %{name: "Field 2", value: "Value 2", inline: true}
          ]
        )

      assert length(embed.fields) == 2
    end
  end
end
