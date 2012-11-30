module Distribution.Server.Features.Tags.Backup (
    tagsBackup,
    tagsToCSV,
    tagsToRecord
  ) where

import Data.Acid (AcidState, update)
import Distribution.Server.Features.Tags.State
import Distribution.Server.Framework.BackupRestore
import Distribution.Server.Framework.BlobStorage (BlobStorage)

import Distribution.Package
import Distribution.Text (display)

import Text.CSV (CSV, Record)
import qualified Data.Map as Map
-- import Data.Set (Set)
import qualified Data.Set as Set

tagsBackup :: BlobStorage -> AcidState PackageTags -> RestoreBackup
tagsBackup store tagsState =
  fromPureRestoreBackup store
    (update tagsState . ReplacePackageTags)
    (updateTagsPure emptyPackageTags)

updateTagsPure :: PackageTags -> PureRestoreBackup PackageTags
updateTagsPure tagsState = PureRestoreBackup {
    pureRestoreEntry = \(BackupByteString entry bs) ->
      if entry == ["tags.csv"]
        then do csv <- importCSV' "tags.csv" bs
                tagsState' <- updateFromCSV csv tagsState
                return (updateTagsPure tagsState')
        else return (updateTagsPure tagsState)
  , pureRestoreFinalize = return tagsState
  }

updateFromCSV :: CSV -> PackageTags -> Restore PackageTags
updateFromCSV = concatM . map fromRecord
  where
    fromRecord :: Record -> PackageTags -> Restore PackageTags
    fromRecord (packageField:tagFields) tagsState | not (null tagFields) = do
      pkgname <- parseText "package name" packageField
      tags <- mapM (parseText "tag") tagFields
      return (setTags pkgname (Set.fromList tags) tagsState)
    fromRecord x _ = fail $ "Invalid tags record: " ++ show x

------------------------------------------------------------------------------
tagsToCSV :: PackageTags -> CSV
tagsToCSV = map (\(p, t) -> tagsToRecord p $ Set.toList t)
          . Map.toList . packageTags

tagsToRecord :: PackageName -> [Tag] -> Record -- [String]
tagsToRecord pkgname tags = display pkgname:map display tags

