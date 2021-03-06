require "rails_helper"

describe Linter::CoffeeScript do
  include ConfigurationHelper

  describe ".can_lint?" do
    context "given a .coffee file" do
      it "returns true" do
        result = Linter::CoffeeScript.can_lint?("foo.coffee")

        expect(result).to eq true
      end
    end

    context "given a .coffee.erb file" do
      it "returns true" do
        result = Linter::CoffeeScript.can_lint?("foo.coffee.erb")

        expect(result).to eq true
      end
    end

    context "given a .coffee.js file" do
      it "returns true" do
        result = Linter::CoffeeScript.can_lint?("foo.coffee.js")

        expect(result).to eq true
      end
    end

    context "given a non-coffee file" do
      it "returns false" do
        result = Linter::CoffeeScript.can_lint?("foo.js")

        expect(result).to eq false
      end
    end
  end

  describe "enabled?" do
    context "when configuration is enabled" do
      it "is enabled" do
        hound_config = double("HoundConfig", linter_enabled?: true)
        linter = build_linter(hound_config: hound_config)

        expect(linter).to be_enabled
      end
    end

    context "when the config has enabled_for to false" do
      it "is not enabled" do
        hound_config = double("HoundConfig", linter_enabled?: false)
        linter = build_linter(hound_config: hound_config)

        expect(linter).not_to be_enabled
      end
    end
  end

  describe "#file_review" do
    it "returns a saved and completed file review" do
      linter = build_linter
      file = build_file("foo")

      result = linter.file_review(file)

      expect(result).to be_persisted
      expect(result).to be_completed
    end

    context "with default configuration" do
      context "for long line" do
        it "returns file review with violations" do
          linter = build_linter
          file = build_file("1" * 81)

          violations = linter.file_review(file).violations
          violation = violations.first

          expect(violations.size).to eq 1
          expect(violation.filename).to eq "test.coffee"
          expect(violation.patch_position).to eq 2
          expect(violation.line_number).to eq 1
          expect(violation.messages).to match_array(
            ["Line exceeds maximum allowed length"]
          )
        end
      end

      context "for trailing whitespace" do
        it "returns file review with violation" do
          expect(violations_in("1   ").first).to match(/trailing whitespace/)
        end
      end

      context "for inconsistent indentation" do
        it "returns file review with violation" do
          code = <<-CODE.strip_heredoc
            class FooBar
              foo: ->
                  "bar"
          CODE

          expect(violations_in(code)).to be_any { |m| m =~ /inconsistent/ }
        end
      end

      context "for non-PascalCase classes" do
        it "returns file review with violation" do
          result = violations_in("class strange_ClassNAME")

          expect(result).to eq(["Class name should be UpperCamelCased"])
        end
      end
    end

    context "with thoughtbot configuration" do
      context "for an empty function" do
        it "returns a file review without violations" do
          code = <<-CODE.strip_heredoc
            class FooBar
              foo: ->
          CODE

          violations = violations_in(
            code,
            config: thoughtbot_configuration_file,
          )

          expect(violations).to be_empty
        end
      end
    end

    context "with violation on unchanged line" do
      it "finds no violations" do
        file = double(
          :file,
          content: "'hello'",
          filename: "lib/test.coffee",
          line_at: nil,
        )

        violations = violations_in(file)

        expect(violations.count).to eq 0
      end
    end

    context "thoughtbot pull request" do
      it "uses the default thoughtbot configuration" do
        spy_on_coffee_lint
        spy_on_file_read

        violations_in("var foo = 'bar'", config: thoughtbot_configuration_file)

        expect(Coffeelint).to have_received(:lint).
          with(anything, thoughtbot_configuration)
      end
    end

    context "a pull request using the legacy configuration repo" do
      it "uses the legacy hound configuration" do
        spy_on_coffee_lint

        violations_in("var foo = 'bar'", config: legacy_configuration_file)

        expect(Coffeelint).to have_received(:lint).
          with(anything, legacy_configuration)
      end
    end

    context "given a `coffee.erb` file" do
      it "lints the file" do
        linter = build_linter
        file = build_file("class strange_ClassNAME", "test.coffee.erb")

        violations = linter.file_review(file).violations
        violation = violations.first

        expect(violations.size).to eq 1
        expect(violation.filename).to eq "test.coffee.erb"
        expect(violation.messages).to match_array [
          "Class name should be UpperCamelCased",
        ]
      end

      it "removes the ERB tags from the file" do
        linter = build_linter
        content = "leonidasLastWords = <%= raise 'hell' %>"
        file = build_file(content, "test.coffee.erb")

        violations = linter.file_review(file).violations

        expect(violations).to be_empty
      end
    end

    private

    def violations_in(content, config: "{}")
      build_linter(build: build_with_stubbed_owner_config(config)).
        file_review(build_file(content)).
        violations.
        flat_map(&:messages)
    end

    def build_file(content, filename = "test.coffee")
      build_commit_file(filename: filename, content: content)
    end

    def legacy_configuration_file
      File.read("spec/support/fixtures/legacy_coffeescript.json")
    end

    def legacy_configuration
      JSON.parse(legacy_configuration_file)
    end

    def thoughtbot_configuration_file
      File.read("spec/support/fixtures/thoughtbot_coffeescript.json")
    end

    def thoughtbot_configuration
      JSON.parse(thoughtbot_configuration_file)
    end

    def spy_on_coffee_lint
      allow(Coffeelint).to receive(:lint).and_return([])
    end
  end

  def build_linter(
    build: build_with_stubbed_owner_config("{}"),
    hound_config: default_hound_config
  )
    Linter::CoffeeScript.new(
      hound_config: hound_config,
      build: build,
    )
  end

  def build_with_stubbed_owner_config(config)
    stub_success_on_repo("organization/style")
    stub_commit_on_repo(
      repo: "organization/style",
      sha: "HEAD",
      files: {
        ".hound.yml" => <<~EOF,
          coffeescript:
            config_file: .coffeescript.json
        EOF
        ".coffeescript.json" => config,
      },
    )
    owner = build(
      :owner,
      config_enabled: true,
      config_repo: "organization/style",
    )
    repo = build(:repo, owner: owner)
    build(:build, repo: repo)
  end

  def default_hound_config
    double("HoundConfig", linter_enabled?: true, content: {})
  end
end
