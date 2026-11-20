module StoryFold (Article(..), Group(..), groupStories, jsonReport, tokenize, matchReason, canonicalURL) where

import Data.Char (isAlphaNum, toLower, ord)
import Data.List (intercalate, sortOn)
import qualified Data.Set as S
import Numeric (showHex)

data Article = Article { title :: String, url :: String, source :: String, published :: String, body :: String } deriving (Eq, Show)
data Group = Group Article [(Article, String)] deriving (Eq, Show)

-- Intentionally deterministic, conservative and language-local. No AI calls.
tokenize :: String -> S.Set String
tokenize = S.fromList . filter (\w -> length w > 1 && w `notElem` stopWords) . words . map clean
  where clean c = if isAlphaNum c then toLower c else ' '
        stopWords = ["the","and","for","with","from","that","this","into","after","before","are","was","has","have","will","its","not","but","new","you","your","about","over","under","how","why"]

canonicalURL :: String -> String
canonicalURL u = base ++ if null kept then "" else "?" ++ intercalate "&" kept
  where
    raw = takeWhile (/= '#') u
    (base, query) = break (== '?') raw
    kept = filter (\p -> let key=map toLower (takeWhile (/= '=') p) in not (take 4 key == "utm_" || key `elem` ["fbclid","gclid"])) (split '&' (drop 1 query))
    split _ [] = []
    split c xs = let (a,b)=break (== c) xs in a:split c (drop 1 b)

similarity :: S.Set String -> S.Set String -> Double
similarity a b | S.null a || S.null b = 0
               | otherwise = fromIntegral (S.size (a `S.intersection` b)) / fromIntegral (S.size (a `S.union` b))

-- Do not group headlines that differ only in numbers or explicit negation.
numbers :: String -> S.Set String
numbers = S.fromList . filter (any (\c -> c >= '0' && c <= '9')) . words

negative :: String -> Bool
negative = any (`elem` ["not","no","never","denies","denied","false"]) . words . map (\c -> if isAlphaNum c then toLower c else ' ')

matchReason :: Int -> Article -> Article -> Maybe String
matchReason threshold a b
  | not (null (url a)) && canonicalURL (url a) == canonicalURL (url b) = Just "Same article URL (tracking parameters ignored); compare revisions below"
  | not (S.null at) && at == bt && numbers (title a) == numbers (title b) && negative (title a) == negative (title b) = Just "Same normalized headline; possible duplicate or republication"
  | length (body a) >= 180 && length (body b) >= 180 && tokenize (body a) == tokenize (body b) && numbers (body a) == numbers (body b) && negative (body a) == negative (body b) = Just "Same normalized body word set; possible republication, review wording"
  | S.size at >= 5 && S.size bt >= 5 && score >= fromIntegral threshold / 100 && numbers (title a) == numbers (title b) && negative (title a) == negative (title b) = Just ("Similar headline words: " ++ show (round (score * 100) :: Int) ++ "% Jaccard overlap; review before treating as identical")
  | otherwise = Nothing
  where at = tokenize (title a); bt = tokenize (title b); score = similarity at bt

groupStories :: Int -> [Article] -> [Group]
groupStories threshold = foldl insert [] . sortOn (\a -> (published a,source a,url a,title a))
  where
    insert [] a = [Group a []]
    insert (Group first rest:gs) a = case matchReason threshold first a of
      Just reason -> Group first (rest ++ [(a,reason)]) : gs
      Nothing -> Group first rest : insert gs a

quote :: String -> String
quote s = '"' : concatMap escape s ++ "\""
  where
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"
    escape c | ord c < 32 || c == '<' || c == '>' || c == '&' = "\\u" ++ replicate (4 - length h) '0' ++ h where h = showHex (ord c) ""
    escape c = [c]

articleJSON :: Article -> String
articleJSON a = "{" ++ intercalate "," [quote k ++ ":" ++ quote v | (k,v)<-[("title",title a),("url",url a),("source",source a),("published",published a),("body",body a)]] ++ "}"

jsonReport :: Int -> [Article] -> String
jsonReport threshold articles = "{\"inputCount\":" ++ show (length articles) ++ ",\"groups\":[" ++ intercalate "," (map render (groupStories threshold articles)) ++ "]}"
  where
    render (Group first rest) = "{\"lead\":" ++ articleJSON first ++ ",\"members\":[" ++ intercalate "," ["{\"article\":" ++ articleJSON a ++ ",\"reason\":" ++ quote reason ++ ",\"changed\":" ++ (if title first /= title a || body first /= body a then "true" else "false") ++ "}" | (a,reason)<-rest] ++ "]}"
