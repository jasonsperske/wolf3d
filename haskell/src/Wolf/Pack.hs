-- | Asset discovery is IO; decoding is kept in the pure codec modules.
module Wolf.Pack (AssetPack(..), findPack, readResource, discoverPack) where
import Control.Exception (IOException, try)
import qualified Data.ByteString as B
import Data.Char (toUpper)
import Data.List (find)
import System.Directory (doesDirectoryExist, listDirectory)
import System.Environment (getExecutablePath)
import System.FilePath ((</>), takeDirectory, normalise)

data AssetPack = AssetPack { packDirectory :: FilePath, packExtension :: String,
                             packFiles :: [FilePath] } deriving Show

findPack :: FilePath -> IO (Either String AssetPack)
findPack dir = do
  result <- try (listDirectory dir) :: IO (Either IOException [FilePath])
  pure $ case result of
    Left e -> Left (show e)
    Right files -> case [ext | ext<-["WL6","WL1"], any ((=="MAPHEAD."++ext) . map toUpper) files] of
      [ext] -> Right (AssetPack dir ext files)
      [] -> Left ("No MAPHEAD.WL1 or MAPHEAD.WL6 in "++dir)
      _ -> Left ("Mixed WL1/WL6 asset sets in "++dir++"; put each edition in its own folder")

readResource :: AssetPack -> String -> IO (Either String B.ByteString)
readResource pack name = case find ((==name++"."++packExtension pack) . map toUpper) (packFiles pack) of
  Nothing -> pure (Left ("Missing "++name++"."++packExtension pack++" in "++packDirectory pack))
  Just file -> do
    result <- try (B.readFile (packDirectory pack </> file))
    pure $ case result of Left e -> Left (show (e :: IOException)); Right bytes -> Right bytes

-- Bundled files win. Development prefers registered over shareware. An existing
-- selected folder with bad data reports an error instead of silently changing games.
discoverPack :: IO (Either String (Maybe AssetPack))
discoverPack = do
  exe <- getExecutablePath
  let base = takeDirectory exe
      candidates = [base </> "assets", base </> "../../assets/registered",
                    base </> "../../assets/shareware", "assets/registered", "assets/shareware"]
      search [] = pure (Right Nothing)
      search (dir:rest) = do
        exists <- doesDirectoryExist dir
        if exists then fmap (fmap Just) (findPack (normalise dir)) else search rest
  search candidates
