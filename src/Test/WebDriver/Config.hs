{-# LANGUAGE OverloadedStrings, RecordWildCards, FlexibleContexts, DataKinds, KindSignatures, MultiParamTypeClasses, FlexibleInstances, UndecidableInstances, TypeFamilies, ConstraintKinds,
             RankNTypes, TypeOperators #-}
module Test.WebDriver.Config(
    -- * WebDriver configuration
      WDConfig, WDConfig'(..), defaultConfig
    -- * SessionHistoryConfig options
    , SessionHistoryConfig, noHistory, unlimitedHistory, onlyMostRecentHistory
    -- * Overloadable configuration
    , WebDriverConfig(..)
    ) where
import Test.WebDriver.Capabilities
import Test.WebDriver.Session

import Data.Default.Class (Default(..))
import Data.String (fromString)
import Data.Aeson
import Data.Vinyl
import Data.Vinyl.TypeLevel

import Control.Monad.Base

import Network.HTTP.Client (Manager, newManager, defaultManagerSettings)
import Network.HTTP.Types (RequestHeaders)


type WDConfig = WDConfig' LegacyWireProtocol

-- |WebDriver session configuration
data WDConfig' (allowedNames :: [CapabilityName] ) (definedNames :: [CapabilityName]) =
  WDConfig' {
     -- |Host name of the WebDriver server for this
     -- session (default 127.0.0.1)
      wdHost :: String
     -- |Port number of the server (default 4444)
    , wdPort :: Int
     -- |Capabilities to use for this session
    , wdCapabilities :: Capabilities Requested definedNames
     -- |Base path for all API requests (default "\/wd\/hub")
    , wdBasePath :: String
    -- |Custom request headers to add to every HTTP request.
    , wdRequestHeaders :: RequestHeaders
    -- |Custom request headers to add *only* to session creation requests. This is usually done
    --  when a WebDriver server requires HTTP auth.
    , wdAuthHeaders :: RequestHeaders
     -- |Specifies behavior of HTTP request/response history. By default we use 'unlimitedHistory'.
    , wdHistoryConfig :: SessionHistoryConfig
     -- |Use the given http-client 'Manager' instead of automatically creating one.
    , wdHTTPManager :: Maybe Manager
     -- |Number of times to retry a HTTP request if it times out (default 0)
    , wdHTTPRetryCount :: Int
  }

instance Default (WDConfig' LegacyWireProtocol '[]) where
    def = WDConfig' {
      wdHost              = "127.0.0.1"
    , wdPort              = 4444
    , wdRequestHeaders    = []
    , wdAuthHeaders       = []
    , wdCapabilities      = emptyCaps
    , wdHistoryConfig     = unlimitedHistory
    , wdBasePath          = "/wd/hub"
    , wdHTTPManager       = Nothing
    , wdHTTPRetryCount    = 0
    }

{- |A default session config connects to localhost on port 4444, and hasn't been
initialized server-side. This value is the same as 'def' but with a less
polymorphic type. -}
defaultConfig :: WDConfig' LegacyWireProtocol '[]
defaultConfig = def


type WebDriverConfigConstraint (allowedNames :: [CapabilityName]) definedNames = (KeysHaveText definedNames, CapsAreParseable definedNames, 'Browser ∈ definedNames)

-- |Class of types that can configure a WebDriver session.
class WebDriverConfigConstraint (AllowedNames c) (DefinedNames c) => WebDriverConfig c where
    type AllowedNames c :: [CapabilityName]
    type DefinedNames c :: [CapabilityName]
    -- |Produces a 'Capabilities' from the given configuration.
    mkCaps :: (MonadBase IO m) => c -> m (Capabilities Requested (DefinedNames c))

    -- |Produces a 'WDSession' from the given configuration.
    mkSession :: MonadBase IO m => c -> m WDSession

instance WebDriverConfigConstraint f f' => WebDriverConfig (WDConfig' f f') where
    type AllowedNames (WDConfig' f f') = f
    type DefinedNames (WDConfig' f f') = f'
    
    mkCaps = return . wdCapabilities

    mkSession WDConfig'{..} = do
      manager <- maybe createManager return wdHTTPManager
      return WDSession { wdSessHost = fromString $ wdHost
                       , wdSessPort = wdPort
                       , wdSessRequestHeaders = wdRequestHeaders
                       , wdSessAuthHeaders = wdAuthHeaders
                       , wdSessBasePath = fromString $ wdBasePath
                       , wdSessId = Nothing
                       , wdSessHist = []
                       , wdSessHistUpdate = wdHistoryConfig
                       , wdSessHTTPManager = manager
                       , wdSessHTTPRetryCount = wdHTTPRetryCount }
      where
        createManager = liftBase $ newManager defaultManagerSettings
