require "open-uri"
require "json"
require "fileutils"

namespace :chrome_for_testing do
  desc "Download a matched Chrome + chromedriver pair into tmp/chrome_for_testing, for system tests on machines with no (or a version-mismatched) system Chrome/chromedriver install"
  task install: :environment do
    require "zip"

    dest_root = Rails.root.join("tmp", "chrome_for_testing")
    FileUtils.mkdir_p(dest_root)

    platform = ChromeForTesting.platform_key
    puts "Detected platform: #{platform}"

    manifest_url = "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
    manifest = JSON.parse(URI.open(manifest_url).read)
    stable = manifest.fetch("channels").fetch("Stable")
    puts "Chrome for Testing #{stable.fetch('version')} (#{platform})"

    # chrome and chromedriver are downloaded from the same "Stable" manifest
    # entry, so the two are always version-matched - a chromedriver from
    # anywhere else (e.g. whatever Selenium Manager falls back to on an old
    # selenium-webdriver gem) has no such guarantee against a Chrome build
    # this task downloaded separately.
    %w[chrome chromedriver].each do |component|
      download = stable.fetch("downloads").fetch(component).find { |d| d["platform"] == platform }
      raise "No #{component} build found for platform #{platform}" unless download

      puts "Downloading #{component}..."
      ChromeForTesting.download_and_extract(component, download.fetch("url"), dest_root, platform)
    end

    chrome_binary = Dir.glob(dest_root.join("chrome-#{platform}", "**", "chrome{,.exe}")).first
    driver_binary = Dir.glob(dest_root.join("chromedriver-#{platform}", "**", "chromedriver{,.exe}")).first
    puts "Chrome binary: #{chrome_binary || '(not found)'}"
    puts "Chromedriver binary: #{driver_binary || '(not found)'}"
  end
end

module ChromeForTesting
  # Platform keys as used by Chrome for Testing's download manifest:
  # https://googlechromelabs.github.io/chrome-for-testing/
  def self.platform_key
    os = RbConfig::CONFIG["host_os"]
    cpu = RbConfig::CONFIG["host_cpu"]

    case os
    when /mingw|mswin|cygwin/
      cpu =~ /x64|x86_64|amd64/ ? "win64" : "win32"
    when /darwin/
      cpu =~ /arm|aarch64/ ? "mac-arm64" : "mac-x64"
    when /linux/
      "linux64"
    else
      raise "Unsupported platform for Chrome for Testing: #{os}/#{cpu}"
    end
  end

  def self.download_and_extract(component, url, dest_root, platform)
    zip_path = dest_root.join("#{component}-#{platform}.zip")
    URI.open(url) do |remote_file|
      File.open(zip_path, "wb") { |file| IO.copy_stream(remote_file, file) }
    end

    extract_dir = dest_root.join("#{component}-#{platform}")
    FileUtils.rm_rf(extract_dir)
    Zip::File.open(zip_path) do |zip_file|
      zip_file.each do |entry|
        entry_path = dest_root.join(entry.name)
        FileUtils.mkdir_p(entry_path.dirname)
        entry.extract(entry_path)
      end
    end
    File.delete(zip_path)

    # The zip's executable permission bits aren't reliably preserved by
    # extraction - the binary (and, for chrome, its helper binaries, which
    # it execs by relative path) need +x on every platform except Windows.
    return if Gem.win_platform?

    Dir.glob(extract_dir.join("**", "*")).each { |path| File.chmod(0755, path) if File.file?(path) }
  end
end
