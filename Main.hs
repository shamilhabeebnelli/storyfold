module Main where
import StoryFold
import Data.Char (chr)
import Numeric (readHex)
import System.Environment (getArgs)
import System.Exit (die)
import Text.Read (readMaybe)

split :: Char -> String -> [String]
split delimiter text = let (a,b)=break (== delimiter) text in a : if null b then [] else split delimiter (tail b)

decode :: String -> Either String String
decode "" = Right ""
decode s = mapM point (split ',' s)
  where point token = case readHex token of
          [(n,"")] | n >= 0 && n <= 0x10ffff && not (n >= 0xd800 && n <= 0xdfff) -> Right (chr n)
          _ -> Left "Invalid Unicode codepoint in bridge input"

parse :: String -> Either String Article
parse row = do
  fields <- mapM decode (split '\t' row)
  case fields of
    [a,b,c,d,e] | not (null a) -> Right (Article a b c d e)
    _ -> Left "Expected five encoded fields and a non-empty title"

main :: IO ()
main = do
  args <- getArgs
  threshold <- case args of
    [] -> pure 78
    [n] -> case readMaybe n of
      Just value | value >= 50 && value <= 100 -> pure value
      _ -> die "Threshold must be an integer from 50 to 100"
    _ -> die "Usage: storyfold [threshold 50..100]. Input is the internal encoded bridge protocol. Use python3 app.py for RSS/Atom/JSON import."
  input <- getContents
  if length input > 32000000 then die "Input exceeds engine size limit" else pure ()
  let rows=lines input
  if length rows > 500 then die "Maximum 500 articles per import" else pure ()
  case mapM parse rows of
    Left problem -> die problem
    Right articles -> putStrLn (jsonReport threshold articles)
