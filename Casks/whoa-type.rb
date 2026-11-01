cask "whoa-type" do
  version "1.0.0"
  sha256 "3a18a3b480d6d50252e0a6d14a70a8ea3a47b994c587129aa089528563928522"

  url "https://github.com/WhoaStudio/whoa-type/releases/download/v#{version}/WhoaType-#{version}-macOS.dmg"
  name "Whoa Type"
  desc "Menu bar keyboard and mouse sound utility"
  homepage "https://github.com/WhoaStudio/whoa-type"

  depends_on macos: :tahoe

  app "Whoa Type.app"

  zap trash: "~/Library/Containers/ugolin-olle.whoa-type"
end
