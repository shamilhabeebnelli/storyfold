module Main where
import StoryFold
import Data.List (isInfixOf)
import System.Exit (exitFailure)

story :: String -> String -> Article
story headline address = Article headline address "Source" "2026-11-20" ""
matched :: Article -> Article -> Bool
matched a b = case matchReason 78 a b of Just _ -> True; Nothing -> False

main :: IO ()
main = do
  let a=story "City opens coastal walking trail for visitors" "https://example.com/a"
      b=story "City coastal walking trail opens for visitors" "https://example.org/b"
      long=unwords (replicate 40 "fictional research story paragraph")
      cases=
        [("exact URL",matched a (story "Completely rewritten headline" "https://example.com/a"))
        ,("tracking ignored",matched a (a{url="https://example.com/a?utm_source=news#top"}))
        ,("query identity retained",canonicalURL "https://x.test/?id=1&utm_source=a" == "https://x.test/?id=1")
        ,("query pages distinct",not (matched (story "One" "https://x.test/?id=1") (story "Two" "https://x.test/?id=2")))
        ,("fuzzy reordering",matched a b)
        ,("punctuation normalized",matched a (story "CITY opens coastal walking trail, for visitors!" ""))
        ,("different numbers separate",not (matched (story "City adds 4 new evening train services" "") (story "City adds 6 new evening train services" "")))
        ,("negation protected",not (matched (story "City council approves coastal walking trail construction" "") (story "City council never approves coastal walking trail construction" "")))
        ,("unrelated separate",not (matched a (story "Student robotics workshop announced at local school" "")))
        ,("short ambiguous headlines separate",not (matched (story "City wins" "") (story "City wins today" "")))
        ,("empty titles not exact",not (matched (story "" "") (story "" "")))
        ,("missing URLs not equal",not (matched (story "One" "") (story "Two" "")))
        ,("long body overlap",matched (a{body=long}) ((story "Fresh headline altogether" ""){body=long}))
        ,("numbered body guarded",not (matched (a{body=long++" 4"}) ((story "Fresh headline altogether" ""){body=long++" 6"})))
        ,("body negation guarded",not (matched (a{body=long++" not"}) ((story "Fresh headline altogether" ""){body=long})))
        ,("Unicode retained",not (null (tokenize "കേരള വാർത്തകൾ")))
        ,("empty import",jsonReport 78 [] == "{\"inputCount\":0,\"groups\":[]}")
        ,("JSON HTML safe",not ("<script>" `isInfixOf` jsonReport 78 [story "<script>" ""]))
        ,("JSON newline escaped","\\n" `isInfixOf` jsonReport 78 [story "a\nb" ""])
        ,("stable input order",groupStories 78 [a,b] == groupStories 78 [b,a])
        ,("conservative representative",length (groupStories 78 [a,b,story "City school student robotics course" ""]) == 2)
        ,("no lost sources",case groupStories 78 [a,b,a] of [Group _ members] -> length members==2; _ -> False)
        ,("threshold respected",case matchReason 100 a (story "City opens coastal walking trail for visitors today" "") of Nothing -> True; _ -> False)
        ,("normalized case",tokenize "COASTAL" == tokenize "coastal")
        ]
  mapM_ (\(name,ok)->putStrLn ((if ok then "PASS " else "FAIL ")++name)) cases
  if all snd cases then putStrLn (show (length cases)++" tests passed") else exitFailure
