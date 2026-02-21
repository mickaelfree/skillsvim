local client = require("skillvim.api.client")

describe("SSE parser", function()
  describe("_parse_sse_buffer", function()
    it("parses a single complete event", function()
      local buffer = 'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}\n\n'
      local events, remainder = client._parse_sse_buffer(buffer)
      assert.equals(1, #events)
      assert.equals("content_block_delta", events[1].event_type)
      assert.equals("Hello", events[1].data.delta.text)
      assert.equals("", remainder)
    end)

    it("handles incomplete event (no trailing double newline)", function()
      local buffer = 'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}'
      local events, remainder = client._parse_sse_buffer(buffer)
      assert.equals(0, #events)
      assert.equals(buffer, remainder)
    end)

    it("parses multiple events in one buffer", function()
      local buffer = 'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}\n\n'
        .. 'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}\n\n'
      local events, remainder = client._parse_sse_buffer(buffer)
      assert.equals(2, #events)
      assert.equals("Hello", events[1].data.delta.text)
      assert.equals(" world", events[2].data.delta.text)
      assert.equals("", remainder)
    end)

    it("splits event across two chunks", function()
      local chunk1 = 'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"He'
      local chunk2 = 'llo"}}\n\n'

      local events1, rem1 = client._parse_sse_buffer(chunk1)
      assert.equals(0, #events1)
      assert.equals(chunk1, rem1)

      local events2, rem2 = client._parse_sse_buffer(rem1 .. chunk2)
      assert.equals(1, #events2)
      assert.equals("Hello", events2[1].data.delta.text)
      assert.equals("", rem2)
    end)

    it("handles message_start event", function()
      local buffer = 'event: message_start\ndata: {"type":"message_start","message":{"id":"msg_123","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100}}}\n\n'
      local events, _ = client._parse_sse_buffer(buffer)
      assert.equals(1, #events)
      assert.equals("message_start", events[1].event_type)
      assert.equals("claude-sonnet-4-20250514", events[1].data.message.model)
      assert.equals(100, events[1].data.message.usage.input_tokens)
    end)

    it("handles message_stop event", function()
      local buffer = 'event: message_stop\ndata: {"type":"message_stop"}\n\n'
      local events, _ = client._parse_sse_buffer(buffer)
      assert.equals(1, #events)
      assert.equals("message_stop", events[1].event_type)
    end)

    it("handles message_delta with usage", function()
      local buffer = 'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":50}}\n\n'
      local events, _ = client._parse_sse_buffer(buffer)
      assert.equals(1, #events)
      assert.equals("message_delta", events[1].event_type)
      assert.equals("end_turn", events[1].data.delta.stop_reason)
      assert.equals(50, events[1].data.usage.output_tokens)
    end)

    it("skips malformed JSON data", function()
      local buffer = "event: ping\ndata: not-json\n\n"
      local events, _ = client._parse_sse_buffer(buffer)
      assert.equals(0, #events)
    end)
  end)

  describe("_handle_anthropic_event", function()
    it("extracts delta text from content_block_delta", function()
      local meta = {}
      local callbacks = { on_delta = function() end }
      local event = {
        event_type = "content_block_delta",
        data = { delta = { type = "text_delta", text = "test" } },
      }
      local text = client._handle_anthropic_event(event, meta, callbacks)
      assert.equals("test", text)
    end)

    it("extracts model from message_start", function()
      local meta = {}
      local callbacks = {}
      local event = {
        event_type = "message_start",
        data = {
          message = {
            model = "claude-sonnet-4-20250514",
            usage = { input_tokens = 42 },
          },
        },
      }
      client._handle_anthropic_event(event, meta, callbacks)
      assert.equals("claude-sonnet-4-20250514", meta.model)
      assert.equals(42, meta.input_tokens)
    end)

    it("extracts stop_reason from message_delta", function()
      local meta = {}
      local callbacks = {}
      local event = {
        event_type = "message_delta",
        data = {
          delta = { stop_reason = "end_turn" },
          usage = { output_tokens = 99 },
        },
      }
      client._handle_anthropic_event(event, meta, callbacks)
      assert.equals("end_turn", meta.stop_reason)
      assert.equals(99, meta.output_tokens)
    end)
  end)
end)
