module StaticHttpRequestsTests exposing (all)

import ApiRoute
import Codec
import DataSource
import DataSource.Http
import Dict
import Expect
import Html
import Json.Decode as JD
import Json.Encode as Encode
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.ContentCache as ContentCache
import Pages.Internal.Platform.Cli exposing (..)
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsPayload)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.Manifest as Manifest
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttp.Request as Request
import PagesHttp
import Path
import ProgramTest exposing (ProgramTest)
import Regex
import RenderRequest
import Secrets
import SimulatedEffect.Cmd
import SimulatedEffect.Http as Http
import SimulatedEffect.Ports
import SimulatedEffect.Task
import Test exposing (Test, describe, test)
import Test.Http


all : Test
all =
    describe "Static Http Requests"
        [ test "initial requests are sent out" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "StaticHttp request for initial are resolved" <|
            \() ->
                start
                    [ ( [ "post-1" ]
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                        --, StaticHttp.succeed 86
                      )
                    ]
                    --|> ProgramTest.simulateHttpOk
                    --    "GET"
                    --    "https://my-cms.com/posts"
                    --    """{ "posts": ["post-1"] }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> expectSuccess
                        [ ( "post-1"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "the stripped JSON from the same request with different decoders is merged so the decoders succeed" <|
            \() ->
                start
                    [ ( [ "post-1" ]
                      , DataSource.map2 Tuple.pair
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                                (Decode.field "stargazer_count" Decode.int)
                            )
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                                (Decode.field "language" Decode.string)
                            )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "language": "Elm" }"""
                    |> expectSuccess
                        [ ( "post-1"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86,"language":"Elm"}"""
                              )
                            ]
                          )
                        ]
        , test "andThen" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.succeed ())
                            |> DataSource.andThen
                                (\_ ->
                                    DataSource.Http.get (Secrets.succeed "NEXT-REQUEST") (Decode.succeed ())
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """null"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "NEXT-REQUEST"
                        """null"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """null"""
                              )
                            , ( get "NEXT-REQUEST"
                              , """null"""
                              )
                            ]
                          )
                        ]
        , test "andThen chain avoids repeat requests" <|
            \() ->
                let
                    getReq url decoder =
                        DataSource.Http.request
                            (Secrets.succeed (get url))
                            decoder

                    pokemonDetailRequest : DataSource.DataSource ()
                    pokemonDetailRequest =
                        getReq
                            "https://pokeapi.co/api/v2/pokemon/"
                            (Decode.list
                                (Decode.field "url" Decode.string
                                    |> Decode.map
                                        (\url ->
                                            getReq url
                                                (Decode.field "image" Decode.string)
                                        )
                                )
                            )
                            |> DataSource.resolve
                            |> DataSource.map (\_ -> ())
                in
                start
                    [ ( [ "elm-pages" ], pokemonDetailRequest )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://pokeapi.co/api/v2/pokemon/"
                        """[
                            {"url": "url1"},
                            {"url": "url2"},
                            {"url": "url3"},
                            {"url": "url4"},
                            {"url": "url5"},
                            {"url": "url6"},
                            {"url": "url7"},
                            {"url": "url8"},
                            {"url": "url9"},
                            {"url": "url10"}
                            ]"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url1"
                        """{"image": "image1.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url2"
                        """{"image": "image2.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url3"
                        """{"image": "image3.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url4"
                        """{"image": "image4.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url5"
                        """{"image": "image5.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url6"
                        """{"image": "image6.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url7"
                        """{"image": "image7.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url8"
                        """{"image": "image8.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url9"
                        """{"image": "image9.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url10"
                        """{"image": "image10.jpg"}"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://pokeapi.co/api/v2/pokemon/"
                              , """[{"url":"url1"},{"url":"url2"},{"url":"url3"},{"url":"url4"},{"url":"url5"},{"url":"url6"},{"url":"url7"},{"url":"url8"},{"url":"url9"},{"url":"url10"}]"""
                              )
                            , ( get "url1"
                              , """{"image":"image1.jpg"}"""
                              )
                            , ( get "url2"
                              , """{"image":"image2.jpg"}"""
                              )
                            , ( get "url3"
                              , """{"image":"image3.jpg"}"""
                              )
                            , ( get "url4"
                              , """{"image":"image4.jpg"}"""
                              )
                            , ( get "url5"
                              , """{"image":"image5.jpg"}"""
                              )
                            , ( get "url6"
                              , """{"image":"image6.jpg"}"""
                              )
                            , ( get "url7"
                              , """{"image":"image7.jpg"}"""
                              )
                            , ( get "url8"
                              , """{"image":"image8.jpg"}"""
                              )
                            , ( get "url9"
                              , """{"image":"image9.jpg"}"""
                              )
                            , ( get "url10"
                              , """{"image":"image10.jpg"}"""
                              )
                            ]
                          )
                        ]
        , test "port is sent out once all requests are finished" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                      )
                    , ( [ "elm-pages-starter" ]
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") starDecoder
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 22 }"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        , ( "elm-pages-starter"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":22}"""
                              )
                            ]
                          )
                        ]
        , test "reduced JSON is sent out" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "you can use elm/json decoders with StaticHttp.unoptimizedRequest" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , method = "GET"
                                , headers = []
                                , body = DataSource.emptyBody
                                }
                            )
                            (DataSource.Http.expectUnoptimizedJson
                                (JD.field "stargazer_count" JD.int)
                            )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{ "stargazer_count": 86, "unused_field": 123 }"""
                              )
                            ]
                          )
                        ]
        , test "plain string" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://example.com/file.txt"
                                , method = "GET"
                                , headers = []
                                , body = DataSource.emptyBody
                                }
                            )
                            (DataSource.Http.expectString Ok)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://example.com/file.txt"
                        "This is a raw text file."
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://example.com/file.txt"
                              , "This is a raw text file."
                              )
                            ]
                          )
                        ]
        , test "Err in String to Result function turns into decode error" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://example.com/file.txt"
                                , method = "GET"
                                , headers = []
                                , body = DataSource.emptyBody
                                }
                            )
                            (DataSource.Http.expectString
                                (\string ->
                                    if String.toUpper string == string then
                                        Ok string

                                    else
                                        Err "String was not uppercased"
                                )
                            )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://example.com/file.txt"
                        "This is a raw text file."
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder ToJsPayload.toJsCodec)
                        (expectErrorsPort
                            """-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages



String was not uppercased"""
                        )
        , test "POST method works" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.request
                            (Secrets.succeed
                                { method = "POST"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , headers = []
                                , body = DataSource.emptyBody
                                }
                            )
                            (Decode.field "stargazer_count" Decode.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "POST"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( { method = "POST"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , headers = []
                                , body = DataSource.emptyBody
                                }
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "json is reduced from andThen chains" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int)
                            |> DataSource.andThen
                                (\_ ->
                                    DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") (Decode.field "stargazer_count" Decode.int)
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 100, "unused_field": 123 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 50, "unused_field": 456 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":100}"""
                              )
                            , ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":50}"""
                              )
                            ]
                          )
                        ]
        , test "reduced json is preserved by StaticHttp.map2" <|
            \() ->
                start
                    [ ( []
                      , DataSource.map2 (\_ _ -> ())
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int))
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") (Decode.field "stargazer_count" Decode.int))
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 100, "unused_field": 123 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 50, "unused_field": 456 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":100}"""
                              )
                            , ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":50}"""
                              )
                            ]
                          )
                        ]
        , test "the port sends out even if there are no http requests" <|
            \() ->
                start
                    [ ( []
                      , DataSource.succeed ()
                      )
                    ]
                    |> expectSuccess [ ( "", [] ) ]
        , test "the port sends out when there are duplicate http requests for the same page" <|
            \() ->
                start
                    [ ( []
                      , DataSource.map2 (\_ _ -> ())
                            (DataSource.Http.get (Secrets.succeed "http://example.com") (Decode.succeed ()))
                            (DataSource.Http.get (Secrets.succeed "http://example.com") (Decode.succeed ()))
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "http://example.com"
                        """null"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "http://example.com"
                              , """null"""
                              )
                            ]
                          )
                        ]
        , test "an error is sent out for decoder failures" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.fail "The user should get this message from the CLI.")
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder ToJsPayload.toJsCodec)
                        (expectErrorsPort
                            """-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages

I encountered some errors while decoding this JSON:

  The user should get this message from the CLI.

    {
      "stargazer_count": 86
    }"""
                        )
        , test "an error is sent for missing secrets from continuation requests" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , DataSource.Http.get
                            (Secrets.succeed
                                (\apiKey ->
                                    "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                )
                                |> Secrets.with "API_KEY"
                            )
                            Decode.string
                            |> DataSource.andThen
                                (\url ->
                                    DataSource.Http.get
                                        (Secrets.succeed
                                            (\missingSecret ->
                                                url ++ "?apiKey=" ++ missingSecret
                                            )
                                            |> Secrets.with "MISSING"
                                        )
                                        (Decode.succeed ())
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        """ "continuation-url" """
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder ToJsPayload.toJsCodec)
                        (expectErrorsPort
                            """-- MISSING SECRET ----------------------------------------------------- elm-pages

I expected to find this Secret in your environment variables but didn't find a match:

Secrets.get "MISSING"
             ^^^^^^^

So maybe MISSING should be API_KEY"""
                        )
        , test "an error is sent for HTTP errors" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.simulateHttpResponse
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Test.Http.httpResponse
                            { statusCode = 404
                            , headers = []
                            , body = ""
                            }
                        )
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder ToJsPayload.toJsCodec)
                        (expectErrorsPort """-- STATIC HTTP ERROR ----------------------------------------------------- elm-pages

I got an error making an HTTP request to this URL: https://api.github.com/repos/dillonkearns/elm-pages

Bad status: 404
Status message: TODO: if you need this, please report to https://github.com/avh4/elm-program-test/issues
Body: 

-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages



Payload sent back invalid JSON
TODO
""")
        , test "uses real secrets to perform request and masked secrets to store and lookup response" <|
            \() ->
                start
                    [ ( []
                      , DataSource.Http.request
                            (Secrets.succeed
                                (\apiKey bearer ->
                                    { url = "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                    , method = "GET"
                                    , headers = [ ( "Authorization", "Bearer " ++ bearer ) ]
                                    , body = DataSource.emptyBody
                                    }
                                )
                                |> Secrets.with "API_KEY"
                                |> Secrets.with "BEARER"
                            )
                            (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.ensureHttpRequest "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        (\request ->
                            request.headers
                                |> Expect.equal [ ( "Authorization", "Bearer XYZ789" ) ]
                        )
                    |> ProgramTest.simulateHttpResponse
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        (Test.Http.httpResponse
                            { statusCode = 200
                            , headers = []
                            , body = """{ "stargazer_count": 86 }"""
                            }
                        )
                    |> expectSuccess
                        [ ( ""
                          , [ ( { method = "GET"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=<API_KEY>"
                                , headers =
                                    [ ( "Authorization", "Bearer <BEARER>" )
                                    ]
                                , body = DataSource.emptyBody
                                }
                              , """{}"""
                              )
                            ]
                          )
                        ]
        , describe "staticHttpCache"
            [ test "it doesn't perform http requests that are provided in the http cache flag" <|
                \() ->
                    startWithHttpCache (Ok ())
                        [ ( { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":86}"""
                          )
                        ]
                        [ ( []
                          , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                          )
                        ]
                        |> expectSuccess
                            [ ( ""
                              , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                                  , """{"stargazer_count":86}"""
                                  )
                                ]
                              )
                            ]
            , test "it ignores unused cache" <|
                \() ->
                    startWithHttpCache (Ok ())
                        [ ( { url = "https://this-is-never-used.example.com/"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":86}"""
                          )
                        ]
                        [ ( []
                          , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                          )
                        ]
                        |> ProgramTest.simulateHttpOk
                            "GET"
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            """{ "stargazer_count": 86 }"""
                        |> expectSuccess
                            [ ( ""
                              , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                                  , """{"stargazer_count":86}"""
                                  )
                                ]
                              )
                            ]
            ]
        , describe "generateFiles"
            [ test "initial requests are sent out" <|
                \() ->
                    startLowLevel
                        [ ApiRoute.succeed
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                                (starDecoder
                                    |> Decode.map
                                        (\starCount ->
                                            { body = "Star count: " ++ String.fromInt starCount
                                            }
                                        )
                                )
                            )
                            |> ApiRoute.literal "test.txt"
                            |> ApiRoute.singleRoute
                        ]
                        (Ok ())
                        []
                        []
                        |> ProgramTest.simulateHttpOk
                            "GET"
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            """{ "stargazer_count": 86 }"""
                        |> expectSuccessNew
                            []
                            [ \success ->
                                success.filesToGenerate
                                    |> Expect.equal
                                        [ { path = [ "test.txt" ]
                                          , content = "Star count: 86"
                                          }
                                        ]
                            ]
            , test "it sends success port when no HTTP requests are needed because they're all cached" <|
                \() ->
                    startLowLevel
                        [ ApiRoute.succeed
                            (DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter")
                                (starDecoder
                                    |> Decode.map
                                        (\starCount ->
                                            { body = "Star count: " ++ String.fromInt starCount
                                            }
                                        )
                                )
                            )
                            |> ApiRoute.literal "test.txt"
                            |> ApiRoute.singleRoute
                        ]
                        (Ok ())
                        [ ( { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":86}"""
                          )
                        , ( { url = "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":23}"""
                          )
                        ]
                        [ ( []
                          , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                          )
                        ]
                        |> expectSuccessNew
                            [ ( ""
                              , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                                  , """{"stargazer_count":86}"""
                                  )
                                ]
                              )
                            ]
                            [ \success ->
                                success.filesToGenerate
                                    |> Expect.equal
                                        [ { path = [ "test.txt" ]
                                          , content = "Star count: 23"
                                          }
                                        ]
                            ]
            ]
        ]


type Route
    = Route String


start : List ( List String, DataSource.DataSource a ) -> ProgramTest (Model Route) Msg Effect
start pages =
    startWithHttpCache (Ok ()) [] pages


startWithHttpCache :
    Result String ()
    -> List ( Request.Request, String )
    -> List ( List String, DataSource.DataSource a )
    -> ProgramTest (Model Route) Msg Effect
startWithHttpCache =
    startLowLevel []


startLowLevel :
    List (ApiRoute.Done ApiRoute.Response)
    -> Result String ()
    -> List ( Request.Request, String )
    -> List ( List String, DataSource.DataSource a )
    -> ProgramTest (Model Route) Msg Effect
startLowLevel apiRoutes documentBodyResult staticHttpCache pages =
    let
        contentCache =
            ContentCache.init Nothing

        config : ProgramConfig Msg () Route () () ()
        config =
            { toJsPort = toJsPort
            , fromJsPort = fromJsPort
            , init = \_ _ _ _ _ -> ( (), Cmd.none )
            , getStaticRoutes =
                --StaticHttp.get (Secrets.succeed "https://my-cms.com/posts")
                --    (Decode.field "posts" (Decode.list (Decode.string |> Decode.map Route)))
                pages
                    |> List.map Tuple.first
                    |> List.map (String.join "/")
                    |> List.map Route
                    |> DataSource.succeed
            , handleRoute = \_ -> DataSource.succeed True
            , urlToRoute = .path >> Route
            , update = \_ _ _ _ _ -> ( (), Cmd.none )
            , data =
                \(Route pageRoute) ->
                    let
                        thing =
                            pages
                                |> Dict.fromList
                                |> Dict.get
                                    (pageRoute
                                        |> String.split "/"
                                        |> List.filter (\pathPart -> pathPart /= "")
                                    )
                    in
                    case thing of
                        Just request ->
                            --\_ _ -> { view = \_ -> { title = "Title", body = Html.text "" }, head = [] }
                            request |> DataSource.map (\_ -> ())

                        Nothing ->
                            Debug.todo <| "Couldn't find page: " ++ pageRoute ++ "\npages: " ++ Debug.toString pages
            , site =
                \_ ->
                    { data = DataSource.succeed ()
                    , canonicalUrl = "canonical-site-url"
                    , manifest = \_ -> manifest
                    , head = \_ -> []
                    }
            , view =
                \page _ ->
                    let
                        thing =
                            pages
                                |> Dict.fromList
                                |> Dict.get
                                    (page.path |> Path.toSegments)
                    in
                    case thing of
                        Just _ ->
                            \_ _ -> { view = \_ -> { title = "Title", body = Html.text "" }, head = [] }

                        Nothing ->
                            Debug.todo <| "Couldn't find page: " ++ Debug.toString page ++ "\npages: " ++ Debug.toString pages
            , subscriptions = \_ _ _ -> Sub.none
            , routeToPath = \(Route route) -> route |> String.split "/"
            , sharedData = DataSource.succeed ()
            , onPageChange = \_ -> Continue
            , apiRoutes = \_ -> apiRoutes
            }

        encodedFlags =
            --{"secrets":
            --        {"API_KEY": "ABCD1234","BEARER": "XYZ789"}, "mode": "prod", "staticHttpCache": {}
            --        }
            Encode.object
                [ ( "secrets"
                  , [ ( "API_KEY", "ABCD1234" )
                    , ( "BEARER", "XYZ789" )
                    ]
                        |> Dict.fromList
                        |> Encode.dict identity Encode.string
                  )
                , ( "mode", Encode.string "prod" )
                , ( "staticHttpCache", encodedStaticHttpCache )
                ]

        encodedStaticHttpCache =
            staticHttpCache
                |> List.map
                    (\( request, httpResponseString ) ->
                        ( Request.hash request, Encode.string httpResponseString )
                    )
                |> Encode.object
    in
    {-
       (Model -> model)
       -> ContentCache.ContentCache metadata view
       -> Result (List BuildError) (List ( PagePath, metadata ))
       -> Config pathKey userMsg userModel metadata view
       -> Decode.Value
       -> ( model, Effect pathKey )
    -}
    ProgramTest.createDocument
        { init = init RenderRequest.FullBuild contentCache config
        , update = update contentCache config
        , view = \_ -> { title = "", body = [] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start (flags (Encode.encode 0 encodedFlags))


flags : String -> JD.Value
flags jsonString =
    case JD.decodeString JD.value jsonString of
        Ok value ->
            value

        Err _ ->
            Debug.todo "Invalid JSON value."


simulateEffects : Effect -> ProgramTest.SimulatedEffect Msg
simulateEffects effect =
    case effect of
        Effect.NoEffect ->
            SimulatedEffect.Cmd.none

        Effect.SendJsData value ->
            SimulatedEffect.Ports.send "toJsPort" (value |> Codec.encoder ToJsPayload.toJsCodec)

        --            toJsPort value |> Cmd.map never
        Effect.Batch list ->
            list
                |> List.map simulateEffects
                |> SimulatedEffect.Cmd.batch

        Effect.FetchHttp ({ unmasked } as requests) ->
            Http.request
                { method = unmasked.method
                , url = unmasked.url
                , headers = unmasked.headers |> List.map (\( key, value ) -> Http.header key value)
                , body =
                    case unmasked.body of
                        StaticHttpBody.EmptyBody ->
                            Http.emptyBody

                        StaticHttpBody.StringBody contentType string ->
                            Http.stringBody contentType string

                        StaticHttpBody.JsonBody value ->
                            Http.jsonBody value
                , expect =
                    PagesHttp.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { request = requests
                                , response = response
                                }
                        )
                , timeout = Nothing
                , tracker = Nothing
                }

        Effect.SendSinglePage _ info ->
            SimulatedEffect.Cmd.batch
                [ info
                    |> Codec.encoder (ToJsPayload.successCodecNew2 "" "")
                    |> SimulatedEffect.Ports.send "toJsPort"
                , SimulatedEffect.Task.succeed ()
                    |> SimulatedEffect.Task.perform (\_ -> Continue)
                ]

        Effect.Continue ->
            --SimulatedEffect.Task.succeed ()
            --    |> SimulatedEffect.Task.perform (\_ -> Continue)
            SimulatedEffect.Cmd.none

        Effect.ReadFile _ ->
            SimulatedEffect.Cmd.none

        Effect.GetGlob _ ->
            SimulatedEffect.Cmd.none


expectErrorsPort : String -> List ToJsPayload -> Expect.Expectation
expectErrorsPort expectedPlainString actualPorts =
    case actualPorts of
        [ ToJsPayload.Errors actualRichTerminalString ] ->
            actualRichTerminalString
                |> List.map .title
                |> String.join "\n"
                |> normalizeErrorExpectEqual expectedPlainString

        [] ->
            Expect.fail "Expected single error port. Didn't receive any ports."

        _ ->
            Expect.fail <| "Expected single error port. Got\n" ++ String.join "\n\n" (List.map Debug.toString actualPorts)


normalizeErrorExpectEqual : String -> String -> Expect.Expectation
normalizeErrorExpectEqual expectedPlainString actualRichTerminalString =
    actualRichTerminalString
        |> Regex.replace
            (Regex.fromString "\u{001B}\\[[0-9;]+m"
                |> Maybe.withDefault Regex.never
            )
            (\_ -> "")
        |> normalizeNewlines
        |> Expect.equal
            (expectedPlainString |> normalizeNewlines)


normalizeNewlines : String -> String
normalizeNewlines string =
    string
        |> Regex.replace
            (Regex.fromString "(\n)+" |> Maybe.withDefault Regex.never)
            (\_ -> "")
        |> Regex.replace
            (Regex.fromString "( )+" |> Maybe.withDefault Regex.never)
            (\_ -> " ")


toJsPort _ =
    Cmd.none


fromJsPort =
    Sub.none


manifest : Manifest.Config
manifest =
    Manifest.init
        { description = "elm-pages - A statically typed site generator."
        , name = "elm-pages docs"
        , startUrl = Path.join []
        , icons = []
        }


starDecoder : Decoder Int
starDecoder =
    Decode.field "stargazer_count" Decode.int


expectSuccess : List ( String, List ( Request.Request, String ) ) -> ProgramTest model msg effect -> Expect.Expectation
expectSuccess expectedRequests previous =
    expectSuccessNew expectedRequests [] previous


expectSuccessNew : List ( String, List ( Request.Request, String ) ) -> List (ToJsPayload.ToJsSuccessPayload -> Expect.Expectation) -> ProgramTest model msg effect -> Expect.Expectation
expectSuccessNew expectedRequests expectations previous =
    previous
        |> ProgramTest.expectOutgoingPortValues
            "toJsPort"
            (Codec.decoder ToJsPayload.toJsCodec)
            (\value ->
                case value of
                    (ToJsPayload.Success portPayload) :: _ ->
                        portPayload
                            |> Expect.all
                                ((\subject ->
                                    subject.pages
                                        |> Expect.equalDicts
                                            (expectedRequests
                                                |> List.map
                                                    (\( url, requests ) ->
                                                        ( url
                                                        , requests
                                                            |> List.map
                                                                (\( request, response ) ->
                                                                    ( Request.hash request, response )
                                                                )
                                                            |> Dict.fromList
                                                        )
                                                    )
                                                |> Dict.fromList
                                            )
                                 )
                                    :: expectations
                                )

                    [ errorPort ] ->
                        Expect.fail <| "Expected success port. Got:\n" ++ Debug.toString errorPort

                    _ ->
                        Expect.fail ("Expected ports to be called once, but instead there were " ++ String.fromInt (List.length value) ++ " calls.")
            )


get : String -> Request.Request
get url =
    { method = "GET"
    , url = url
    , headers = []
    , body = DataSource.emptyBody
    }
