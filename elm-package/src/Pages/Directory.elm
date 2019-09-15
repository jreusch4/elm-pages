module Pages.Directory exposing (Directory, build, includes, indexPath)

import Pages.PagePath as PagePath exposing (PagePath)


type Directory key
    = Directory (List (PagePath key)) (List String)


includes : Directory key -> PagePath key -> Bool
includes (Directory allPagePaths directoryPath) pagePath =
    allPagePaths
        |> List.filter
            (\path ->
                PagePath.toString path
                    |> String.startsWith (toString directoryPath)
            )
        |> List.member pagePath


indexPath : Directory key -> String
indexPath (Directory allPagePaths directoryPath) =
    toString directoryPath


toString : List String -> String
toString rawPath =
    "/"
        ++ (rawPath |> String.join "/")


build : key -> List (PagePath key) -> List String -> Directory key
build key allPagePaths path =
    Directory allPagePaths path
