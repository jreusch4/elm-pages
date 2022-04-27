module Effect exposing (Effect(..), batch, fromCmd, map, none, perform)

import Browser.Navigation
import Http
import Json.Decode as Decode
import Url exposing (Url)


type Effect msg
    = None
    | Cmd (Cmd msg)
    | Batch (List (Effect msg))
    | GetStargazers (Result Http.Error Int -> msg)
    | FetchRouteData
        { body : Maybe { contentType : String, body : String }
        , path : Maybe String
        , toMsg : Result Http.Error Url -> msg
        }
    | Submit
        { values : List ( String, String )
        , path : Maybe (List String)
        , method : Maybe String
        , toMsg : Result Http.Error Url -> msg
        }


type alias RequestInfo =
    { contentType : String
    , body : String
    }


none : Effect msg
none =
    None


batch : List (Effect msg) -> Effect msg
batch =
    Batch


fromCmd : Cmd msg -> Effect msg
fromCmd =
    Cmd


map : (a -> b) -> Effect a -> Effect b
map fn effect =
    case effect of
        None ->
            None

        Cmd cmd ->
            Cmd (Cmd.map fn cmd)

        Batch list ->
            Batch (List.map (map fn) list)

        GetStargazers toMsg ->
            GetStargazers (toMsg >> fn)

        FetchRouteData fetchInfo ->
            FetchRouteData
                { body = fetchInfo.body
                , path = fetchInfo.path
                , toMsg = fetchInfo.toMsg >> fn
                }

        Submit fetchInfo ->
            Submit
                { values = fetchInfo.values
                , path = fetchInfo.path
                , method = fetchInfo.method
                , toMsg = fetchInfo.toMsg >> fn
                }


perform :
    { fetchRouteData :
        { body : Maybe { contentType : String, body : String }
        , path : Maybe String
        , toMsg : Result Http.Error Url -> pageMsg
        }
        -> Cmd msg
    , submit :
        { values : List ( String, String )
        , encType : Maybe String
        , method : Maybe String
        , path : Maybe String
        , toMsg : Result Http.Error Url -> pageMsg
        }
        -> Cmd msg
    , fromPageMsg : pageMsg -> msg
    , key : Browser.Navigation.Key
    }
    -> Effect pageMsg
    -> Cmd msg
perform ({ fromPageMsg, key } as helpers) effect =
    case effect of
        None ->
            Cmd.none

        Cmd cmd ->
            Cmd.map fromPageMsg cmd

        Batch list ->
            Cmd.batch (List.map (perform helpers) list)

        GetStargazers toMsg ->
            Http.get
                { url =
                    "https://api.github.com/repos/dillonkearns/elm-pages"
                , expect = Http.expectJson (toMsg >> fromPageMsg) (Decode.field "stargazers_count" Decode.int)
                }

        FetchRouteData fetchInfo ->
            helpers.fetchRouteData
                { body = fetchInfo.body
                , path = fetchInfo.path
                , toMsg = fetchInfo.toMsg
                }

        Submit record ->
            helpers.submit
                { values = record.values
                , path = Nothing --fetchInfo.path
                , method = record.method
                , encType = Nothing -- TODO
                , toMsg = record.toMsg
                }
