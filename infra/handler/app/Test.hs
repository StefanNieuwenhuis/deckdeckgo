{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

import Control.Monad
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.HTTP.Types as HTTP
import Servant.API
import Servant.Client
import DeckGo.Handler
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.HashMap.Strict as HMS
import System.Environment (getArgs)

main :: IO ()
main = do
  [p] <- getArgs

  b <- T.readFile p

  manager' <- newManager defaultManagerSettings

  let clientEnv = mkClientEnv manager' (BaseUrl Http "localhost" 8080 "")
  let someFirebaseId = FirebaseId "the-uid" -- from ./token
  let someUserId = UserId someFirebaseId
  let someDeck = Deck
        { deckSlides = []
        , deckDeckname = Deckname "foo"
        , deckOwnerId = someUserId
        , deckAttributes = HMS.empty
        }

  runClientM usersGet' clientEnv >>= \case
    Left err -> error $ "Expected users, got error: " <> show err
    Right [] -> pure ()
    Right decks -> error $ "Expected 0 users, got: " <> show decks

  runClientM (decksGet' b (Just someUserId)) clientEnv >>= \case
    Left err -> error $ "Expected decks, got error: " <> show err
    Right [] -> pure ()
    Right decks -> error $ "Expected 0 decks, got: " <> show decks

  deckId <- runClientM (decksPost' b someDeck) clientEnv >>= \case
    Left err -> error $ "Expected new deck, got error: " <> show err
    Right (Item deckId _) -> pure deckId

  let someSlide = Slide (Just "foo") "bar" HMS.empty

  slideId <- runClientM (slidesPost' b deckId someSlide) clientEnv >>= \case
    Left err -> error $ "Expected new slide, got error: " <> show err
    Right (Item slideId _) -> pure slideId

  let newDeck = Deck { deckSlides = [ slideId ], deckDeckname = Deckname "bar", deckOwnerId = someUserId, deckAttributes = HMS.singleton "foo" "bar" }

  runClientM (decksPut' b deckId newDeck) clientEnv >>= \case
    Left err -> error $ "Expected updated deck, got error: " <> show err
    Right {} -> pure ()

  runClientM (decksGet' b (Just someUserId)) clientEnv >>= \case
    Left err -> error $ "Expected decks, got error: " <> show err
    Right decks ->
      if decks == [Item deckId newDeck] then pure () else (error $ "Expected updated decks, got: " <> show decks)

  runClientM (decksGetDeckId' b deckId) clientEnv >>= \case
    Left err -> error $ "Expected decks, got error: " <> show err
    Right deck ->
      if deck == (Item deckId newDeck) then pure () else (error $ "Expected get deck, got: " <> show deck)

  let updatedSlide = Slide Nothing "quux" HMS.empty

  runClientM (slidesPut' b deckId slideId updatedSlide) clientEnv >>= \case
    Left err -> error $ "Expected new slide, got error: " <> show err
    Right {} -> pure ()

  runClientM (slidesPut' b deckId slideId updatedSlide) clientEnv >>= \case
    Left err -> error $ "Expected new slide, got error: " <> show err
    Right {} -> pure ()

  runClientM (slidesGetSlideId' b deckId slideId) clientEnv >>= \case
    Left err -> error $ "Expected updated slide, got error: " <> show err
    Right slide ->
      if slide == (Item slideId updatedSlide) then pure () else (error $ "Expected updated slide, got: " <> show slide)

  runClientM (slidesDelete' b deckId slideId) clientEnv >>= \case
    Left err -> error $ "Expected slide delete, got error: " <> show err
    Right {} -> pure ()

  runClientM (decksDelete' b deckId) clientEnv >>= \case
    Left err -> error $ "Expected deck delete, got error: " <> show err
    Right {} -> pure ()

  runClientM (decksGet' b (Just someUserId)) clientEnv >>= \case
    Left err -> error $ "Expected no decks, got error: " <> show err
    Right decks ->
      if decks == [] then pure () else (error $ "Expected no decks, got: " <> show decks)

  let someUser = User { userFirebaseId = someFirebaseId, userUsername = Just (Username "joseph") }

  runClientM (usersPost' b someUser) clientEnv >>= \case
    Left err -> error $ "Expected user, got error: " <> show err
    Right (Item userId user) ->
      unless (user == someUser && userId == someUserId) $
        error $ "Expected same user, got: " <> show user

  runClientM (usersPost' b someUser) clientEnv >>= \case
    Left (FailureResponse resp) ->
      unless (HTTP.statusCode (responseStatusCode resp) == 409) $
        error $ "Got unexpected response: " <> show resp
    Left err -> error $ "Expected 409, got error: " <> show err
    Right item -> error $ "Expected failure, got success: " <> show item


  -- TODO: test that creating user with token that has different user as sub
  -- fails

usersGet' :: ClientM [Item UserId User]
_usersGetUserId' :: UserId -> ClientM (Item UserId User)
usersPost' :: T.Text -> User -> ClientM (Item UserId User)
_usersPut' :: T.Text -> UserId -> User -> ClientM (Item UserId User)
_usersDelete' :: T.Text -> UserId -> ClientM ()

decksGet' :: T.Text -> Maybe UserId -> ClientM [Item DeckId Deck]
decksGetDeckId' :: T.Text -> DeckId -> ClientM (Item DeckId Deck)
decksPost' :: T.Text -> Deck -> ClientM (Item DeckId Deck)
decksPut' :: T.Text -> DeckId -> Deck -> ClientM (Item DeckId Deck)
decksDelete' :: T.Text -> DeckId -> ClientM ()

slidesGetSlideId' :: T.Text -> DeckId -> SlideId -> ClientM (Item SlideId Slide)
slidesPost' :: T.Text -> DeckId -> Slide -> ClientM (Item SlideId Slide)
slidesPut' :: T.Text -> DeckId -> SlideId -> Slide -> ClientM (Item SlideId Slide)
slidesDelete' :: T.Text -> DeckId -> SlideId -> ClientM ()
((
  usersGet' :<|>
  _usersGetUserId' :<|>
  usersPost' :<|>
  _usersPut' :<|>
  _usersDelete'
  ) :<|>
  (
  decksGet' :<|>
  decksGetDeckId' :<|>
  decksPost' :<|>
  decksPut' :<|>
  decksDelete'
  ) :<|>
  (
  slidesGetSlideId' :<|>
  slidesPost' :<|>
  slidesPut' :<|>
  slidesDelete'
  )
  ) = client api
