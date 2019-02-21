module App.Modals.ConnectModal exposing
    ( ConnectingTarget(..)
    , Model
    , WithConnectModal
    , defaultModel
    , initModel
    , update
    , view
    )

import App.Commands
import App.I18n.Keys as I18nKeys
import App.Markdown
import App.Messages as AppMsg exposing (Msg(CloseModal))
import App.Modals.ConnectModalMsg as ConnectModalMsg exposing (Msg(..))
import App.Server.Graph
import App.Server.Post
import App.Submodels.Context exposing (Context)
import App.Submodels.LocalCotos exposing (LocalCotos)
import App.Submodels.Modals exposing (Modal(ConnectModal), Modals)
import App.Types.Connection exposing (Direction(..))
import App.Types.Coto exposing (Coto, CotoContent, CotoId)
import App.Types.Post exposing (Post)
import App.Types.Timeline
import App.Update.Post
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Maybe exposing (andThen)
import Utils.HtmlUtil exposing (materialIcon)
import Utils.Modal
import Utils.StringUtil
import Utils.UpdateUtil exposing (..)


type ConnectingTarget
    = None
    | Coto Coto
    | NewPost CotoContent


type alias Model =
    { target : ConnectingTarget
    , selectedCotos : List Coto
    , direction : Direction
    , linkingPhrase : String
    , onPosted : AppMsg.Msg
    }


defaultModel : Model
defaultModel =
    { target = None
    , selectedCotos = []
    , direction = Inbound
    , linkingPhrase = ""
    , onPosted = AppMsg.NoOp
    }


initModel : ConnectingTarget -> List Coto -> Direction -> Model
initModel target selectedCotos direction =
    { defaultModel
        | target = target
        , selectedCotos = selectedCotos
        , direction = direction
    }


getLinkingPhrase : Model -> Maybe String
getLinkingPhrase model =
    if Utils.StringUtil.isBlank model.linkingPhrase then
        Nothing

    else
        Just model.linkingPhrase


type alias WithConnectModal model =
    { model | connectModal : Model }


view : Context context -> Model -> Html AppMsg.Msg
view context model =
    model
        |> modalConfig context
        |> Utils.Modal.view "connect-modal"


modalConfig : Context context -> Model -> Utils.Modal.Config AppMsg.Msg
modalConfig context model =
    let
        primaryButtonId =
            "connect-modal-primary-button"
    in
    { closeMessage = CloseModal
    , title = text (context.i18nText I18nKeys.ConnectModal_Title)
    , content = modalContent context model
    , buttons =
        case model.target of
            None ->
                []

            Coto coto ->
                [ button
                    [ id primaryButtonId
                    , class "button button-primary"
                    , autofocus True
                    , onClick
                        (AppMsg.ConnectModalMsg
                            (Connect coto model.selectedCotos)
                        )
                    ]
                    [ text (context.i18nText I18nKeys.ConnectModal_Connect) ]
                ]

            NewPost content ->
                [ button
                    [ id primaryButtonId
                    , class "button button-primary"
                    , autofocus True
                    , onClick
                        (AppMsg.ConnectModalMsg
                            (PostAndConnectToSelection content)
                        )
                    ]
                    [ text (context.i18nText I18nKeys.ConnectModal_PostAndConnect) ]
                ]
    }


modalContent : Context context -> Model -> Html AppMsg.Msg
modalContent context model =
    let
        selectedCotosHtml =
            Html.Keyed.node
                "div"
                [ class "selected-cotos" ]
                (List.map
                    (\coto ->
                        ( toString coto.id
                        , div [ class "coto-content" ]
                            [ contentDiv coto.summary coto.content ]
                        )
                    )
                    model.selectedCotos
                )

        targetHtml =
            case model.target of
                None ->
                    div [] []

                Coto coto ->
                    div [ class "target-coto coto-content" ]
                        [ contentDiv coto.summary coto.content ]

                NewPost content ->
                    div [ class "target-new-post coto-content" ]
                        [ contentDiv content.summary content.content ]

        ( start, end ) =
            case model.direction of
                Outbound ->
                    ( targetHtml, selectedCotosHtml )

                Inbound ->
                    ( selectedCotosHtml, targetHtml )
    in
    div []
        [ div
            [ class "tools" ]
            [ button
                [ class "button reverse-direction"
                , onClick (AppMsg.ConnectModalMsg ReverseDirection)
                ]
                [ text (context.i18nText I18nKeys.ConnectModal_Reverse) ]
            ]
        , div
            [ class "start" ]
            [ span [ class "node-title" ] [ text "From:" ]
            , start
            ]
        , div
            [ class "connection" ]
            [ div [ class "arrow" ]
                [ materialIcon "arrow_downward" Nothing ]
            , div [ class "linking-phrase" ]
                [ input
                    [ type_ "text"
                    , class "u-full-width"
                    , placeholder (context.i18nText I18nKeys.ConnectModal_LinkingPhrase)
                    , maxlength App.Types.Coto.cotonomaNameMaxlength
                    , onInput (AppMsg.ConnectModalMsg << LinkingPhraseInput)
                    ]
                    []
                ]
            ]
        , div
            [ class "end" ]
            [ span [ class "node-title" ] [ text "To:" ]
            , end
            ]
        ]


contentDiv : Maybe String -> String -> Html AppMsg.Msg
contentDiv maybeSummary content =
    maybeSummary
        |> Maybe.map
            (\summary ->
                div [ class "coto-summary" ] [ text summary ]
            )
        |> Maybe.withDefault (App.Markdown.markdown content)
        |> (\contentDiv -> div [ class "coto-inner" ] [ contentDiv ])


type alias UpdateModel model =
    LocalCotos (Modals (WithConnectModal model))


update : Context context -> ConnectModalMsg.Msg -> UpdateModel model -> ( UpdateModel model, Cmd AppMsg.Msg )
update context msg ({ connectModal } as model) =
    case msg of
        ReverseDirection ->
            let
                direction =
                    case connectModal.direction of
                        Outbound ->
                            Inbound

                        Inbound ->
                            Outbound
            in
            { model | connectModal = { connectModal | direction = direction } }
                |> withoutCmd

        LinkingPhraseInput input ->
            { model | connectModal = { connectModal | linkingPhrase = input } }
                |> withoutCmd

        Connect target objects ->
            model
                |> App.Submodels.LocalCotos.connect
                    context.session
                    target
                    objects
                    model.connectModal.direction
                    (getLinkingPhrase model.connectModal)
                |> App.Submodels.Modals.closeModal ConnectModal
                |> withCmd
                    (\model ->
                        App.Server.Graph.connect
                            context.clientId
                            (Maybe.map .key model.cotonoma)
                            target.id
                            (List.map .id objects)
                            model.connectModal.direction
                            (getLinkingPhrase model.connectModal)
                    )

        PostAndConnectToSelection content ->
            model
                |> App.Submodels.Modals.closeModal ConnectModal
                |> postAndConnectToSelection context content

        PostedAndConnectToSelection postId (Ok post) ->
            model
                |> App.Submodels.Modals.clearModals
                |> App.Update.Post.onPosted context postId post
                |> chain (connectPostToSelection context post)
                |> addCmd (\_ -> App.Commands.sendMsg model.connectModal.onPosted)

        PostedAndConnectToSelection postId (Err _) ->
            model |> withoutCmd


postAndConnectToSelection :
    Context context
    -> CotoContent
    -> UpdateModel model
    -> ( UpdateModel model, Cmd AppMsg.Msg )
postAndConnectToSelection context content model =
    let
        ( newTimeline, newPost ) =
            App.Types.Timeline.post context False content model.timeline

        tag =
            AppMsg.ConnectModalMsg
                << PostedAndConnectToSelection newTimeline.postIdCounter
    in
    { model | timeline = newTimeline }
        |> withCmds
            (\model ->
                [ App.Commands.scrollTimelineToBottom (\_ -> AppMsg.NoOp)
                , App.Server.Post.post context.clientId context.cotonoma tag newPost
                ]
            )


connectPostToSelection :
    Context context
    -> Post
    -> UpdateModel model
    -> ( UpdateModel model, Cmd AppMsg.Msg )
connectPostToSelection context post model =
    post.cotoId
        |> Maybe.andThen (\cotoId -> App.Submodels.LocalCotos.getCoto cotoId model)
        |> Maybe.map
            (\target ->
                let
                    objects =
                        App.Submodels.LocalCotos.getSelectedCotos context model
                in
                ( App.Submodels.LocalCotos.connect
                    context.session
                    target
                    objects
                    model.connectModal.direction
                    (getLinkingPhrase model.connectModal)
                    model
                , App.Server.Graph.connect
                    context.clientId
                    (Maybe.map .key model.cotonoma)
                    target.id
                    (List.map .id objects)
                    model.connectModal.direction
                    (getLinkingPhrase model.connectModal)
                )
            )
        |> Maybe.withDefault ( model, Cmd.none )
