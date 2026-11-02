cask "whoa-type" do
  version "1.0.2"
  sha256 "75926e95bd6aaed3167ef427215e11a2e62cb9e21126f0e17c679235c4b06853"

  url "https://github.com/WhoaStudio/whoa-type/releases/download/v#{version}/WhoaType-#{version}-macOS.dmg"
  name "Whoa Type"
  desc "Menu bar keyboard and mouse sound utility"
  homepage "https://github.com/WhoaStudio/whoa-type"

  depends_on macos: :tahoe

  app "Whoa Type.app"

  zap trash: "~/Library/Containers/ugolin-olle.whoa-type"
end
