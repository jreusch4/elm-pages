module Pages.Internal.StaticHttpBody exposing (Body(..), encode)

import Json.Encode as Encode


type Body
    = EmptyBody
    | StringBody String


encode : Body -> Encode.Value
encode body =
    case body of
        EmptyBody ->
            encodeWithType "empty" []

        StringBody content ->
            encodeWithType "string"
                [ ( "content", Encode.string content )
                ]


encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields
