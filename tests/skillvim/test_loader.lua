local loader = require("skillvim.skills.loader")

describe("skills.loader", function()
  local fixture_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
    .. "/fixtures/skills/test-skill/SKILL.md"

  describe("parse_frontmatter", function()
    it("parses a valid SKILL.md frontmatter", function()
      local fm, err = loader.parse_frontmatter(fixture_path)
      assert.is_nil(err)
      assert.is_not_nil(fm)
      assert.equals("test-skill", fm.name)
      assert.is_truthy(fm.description:find("test skill"))
      assert.equals("MIT", fm.license)
    end)

    it("parses nested metadata", function()
      local fm, _ = loader.parse_frontmatter(fixture_path)
      assert.is_not_nil(fm.metadata)
      assert.equals("skillvim", fm.metadata.author)
      assert.equals("testing", fm.metadata.trigger)
      assert.equals("*.test.lua", fm.metadata.globs)
    end)

    it("returns error for missing file", function()
      local fm, err = loader.parse_frontmatter("/nonexistent/path/SKILL.md")
      assert.is_nil(fm)
      assert.is_truthy(err)
    end)

    it("returns error for file without frontmatter", function()
      -- Create a temp file without frontmatter
      local tmp = vim.fn.tempname()
      vim.fn.writefile({ "# No frontmatter here", "", "Just content." }, tmp)
      local fm, err = loader.parse_frontmatter(tmp)
      assert.is_nil(fm)
      assert.is_truthy(err:find("No frontmatter"))
      vim.fn.delete(tmp)
    end)
  end)

  describe("load_full", function()
    it("loads frontmatter and body", function()
      local data, err = loader.load_full(fixture_path)
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.equals("test-skill", data.frontmatter.name)
      assert.is_truthy(data.body:find("# Test Skill"))
      assert.is_truthy(data.body:find("Arrange%-Act%-Assert"))
      assert.equals(fixture_path, data.path)
    end)
  end)

  describe("_parse_yaml_simple", function()
    it("parses simple key-value pairs", function()
      local result = loader._parse_yaml_simple({
        'name: my-skill',
        'description: "A simple skill"',
        'license: MIT',
      })
      assert.equals("my-skill", result.name)
      assert.equals("A simple skill", result.description)
      assert.equals("MIT", result.license)
    end)

    it("strips quotes from values", function()
      local result = loader._parse_yaml_simple({
        "name: 'single-quoted'",
        'description: "double-quoted"',
      })
      assert.equals("single-quoted", result.name)
      assert.equals("double-quoted", result.description)
    end)

    it("parses nested tables", function()
      local result = loader._parse_yaml_simple({
        "name: test",
        "metadata:",
        "  author: john",
        "  trigger: build",
      })
      assert.equals("test", result.name)
      assert.is_not_nil(result.metadata)
      assert.equals("john", result.metadata.author)
      assert.equals("build", result.metadata.trigger)
    end)

    it("handles boolean and number values", function()
      local result = loader._parse_yaml_simple({
        "name: test",
        "metadata:",
        "  auto_invoke: true",
        "  version: 42",
      })
      assert.is_true(result.metadata.auto_invoke)
      assert.equals(42, result.metadata.version)
    end)
  end)
end)
