cask "whoa-type" do
  version "1.2"
  sha256 "382f65254e87657e2327e548c34b559185e37fdd0ecf95997f9fe71702542d17"

  url "https://github.com/WhoaStudio/Whoa-Typer/releases/download/v#{version}/WhoaType-#{version}-macOS.dmg"
  name "Whoa Type"
  desc "Menu bar keyboard and mouse sound utility"
  homepage "https://github.com/WhoaStudio/Whoa-Typer"

  depends_on macos: :tahoe

  app "Whoa Type.app"

  zap trash: "~/Library/Containers/ugolin-olle.whoa-type"
end
