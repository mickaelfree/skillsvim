local resolver = require("skillvim.skills.resolver")

describe("skills.resolver", function()
  describe("_tokenize", function()
    it("splits text into words", function()
      local words = resolver._tokenize("Hello world testing")
      assert.equals(3, #words)
    end)

    it("filters stop words", function()
      local words = resolver._tokenize("the quick brown fox is not a dog")
      -- "the", "is", "not", "a" are stop words
      local word_set = {}
      for _, w in ipairs(words) do
        word_set[w] = true
      end
      assert.is_nil(word_set["the"])
      assert.is_nil(word_set["is"])
      assert.is_nil(word_set["a"])
      assert.is_truthy(word_set["quick"])
      assert.is_truthy(word_set["brown"])
    end)

    it("returns empty for nil input", function()
      local words = resolver._tokenize(nil)
      assert.equals(0, #words)
    end)
  end)

  describe("_filetype_matches_ext", function()
    it("matches typescript to ts", function()
      assert.is_true(resolver._filetype_matches_ext("typescript", "ts"))
    end)

    it("matches typescriptreact to tsx", function()
      assert.is_true(resolver._filetype_matches_ext("typescriptreact", "tsx"))
    end)

    it("matches lua to lua", function()
      assert.is_true(resolver._filetype_matches_ext("lua", "lua"))
    end)

    it("matches c to c and h", function()
      assert.is_true(resolver._filetype_matches_ext("c", "c"))
      assert.is_true(resolver._filetype_matches_ext("c", "h"))
    end)

    it("does not match unrelated types", function()
      assert.is_false(resolver._filetype_matches_ext("python", "lua"))
    end)
  end)

  describe("_score", function()
    it("returns high score for trigger match", function()
      local entry = {
        name = "test-skill",
        description = "A testing skill",
        metadata = { trigger = "testing" },
      }
      local score = resolver._score("I need help with testing", entry, nil)
      assert.equals(1.0, score)
    end)

    it("returns 0.5 for exact name match", function()
      local entry = {
        name = "react",
        description = "UI framework",
        metadata = nil,
      }
      local score = resolver._score("help with react component", entry, nil)
      assert.is_true(score >= 0.5)
    end)

    it("returns partial score for name part match", function()
      local entry = {
        name = "react-typescript",
        description = "React with TypeScript",
        metadata = nil,
      }
      local score = resolver._score("help with react", entry, nil)
      assert.is_true(score > 0)
    end)

    it("returns 0 for no match", function()
      local entry = {
        name = "rust-ownership",
        description = "Rust ownership and lifetimes patterns",
        metadata = nil,
      }
      local score = resolver._score("help with python django", entry, nil)
      assert.equals(0, score)
    end)

    it("boosts score for filetype match via globs", function()
      local entry = {
        name = "lua-patterns",
        description = "Lua scripting patterns",
        metadata = { globs = "*.lua" },
      }
      local score_with_ft = resolver._score("help with modules", entry, "lua")
      local score_without_ft = resolver._score("help with modules", entry, "python")
      assert.is_true(score_with_ft > score_without_ft)
    end)

    it("scores keyword overlap in description", function()
      local entry = {
        name = "generic",
        description = "Best practices for memory management and optimization",
        metadata = nil,
      }
      local score = resolver._score("memory optimization tips", entry, nil)
      assert.is_true(score > 0)
    end)
  end)
end)
