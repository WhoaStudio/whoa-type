cask "whoa-type" do
  version "1.0.1"
  sha256 "98260c2dc59f8ae0d19d796f9a627c2b54bb8777ba384a2c7070a7c3aa5780b5"

  url "https://github.com/WhoaStudio/whoa-type/releases/download/v#{version}/WhoaType-#{version}-macOS.dmg"
  name "Whoa Type"
  desc "Menu bar keyboard and mouse sound utility"
  homepage "https://github.com/WhoaStudio/whoa-type"

  depends_on macos: :tahoe

  app "Whoa Type.app"

  zap trash: "~/Library/Containers/ugolin-olle.whoa-type"
end
