module CTT where

import Control.Applicative
import Data.List
import Data.Maybe
import Text.PrettyPrint as PP

import Connections

--------------------------------------------------------------------------------
-- | Terms

data Loc = Loc { locFile :: String
               , locPos  :: (Int,Int) }
  deriving Eq

type Ident  = String
type Label  = String

-- Branch of the form: c x1 .. xn -> e
type Branch = (Label,([Ident],Ter))

-- Telescope (x1 : A1) .. (xn : An)
type Tele   = [(Ident,Ter)]

-- Labelled sum: c (x1 : A1) .. (xn : An)
type LblSum = [(Ident,Tele)]

-- Declarations: x : A = e
type Decl   = (Ident,(Ter,Ter))

declIdents :: [Decl] -> [Ident]
declIdents decls = [ x | (x,_) <- decls ]

declTers :: [Decl] -> [Ter]
declTers decls = [ d | (_,(_,d)) <- decls ]

declTele :: [Decl] -> Tele
declTele decls = [ (x,t) | (x,(t,_)) <- decls ]

declDefs :: [Decl] -> [(Ident,Ter)]
declDefs decls = [ (x,d) | (x,(_,d)) <- decls ]

-- Terms
data Ter = App Ter Ter
         | Pi Ter
         | Lam Ident Ter Ter
         | Where Ter [Decl]
         | Var Ident
         | U
           -- Sigma types:
         | Sigma Ter
         | SPair Ter Ter
         | Fst Ter
         | Snd Ter
           -- constructor c Ms
         | Con Label [Ter]
           -- branches c1 xs1  -> M1,..., cn xsn -> Mn
         | Split Loc Ter [Branch]
           -- labelled sum c1 A1s,..., cn Ans (assumes terms are constructors)
         | Sum Loc Ident LblSum
           -- undefined
         | Undef Loc

           -- Id type
         | IdP Ter Ter Ter
         | Path Name Ter
         | AppFormula Ter Formula
           -- Kan Composition
         | Comp Ter Ter (System Ter)
         | Trans Ter Ter
  deriving Eq

-- For an expression t, returns (u,ts) where u is no application and t = u ts
unApps :: Ter -> (Ter,[Ter])
unApps = aux []
  where aux :: [Ter] -> Ter -> (Ter,[Ter])
        aux acc (App r s) = aux (s:acc) r
        aux acc t         = (t,acc)

mkApps :: Ter -> [Ter] -> Ter
mkApps (Con l us) vs = Con l (us ++ vs)
mkApps t ts          = foldl App t ts

mkWheres :: [[Decl]] -> Ter -> Ter
mkWheres []     e = e
mkWheres (d:ds) e = Where (mkWheres ds e) d

--------------------------------------------------------------------------------
-- | Values

data Val = VU
         | Ter Ter Env
         | VPi Val Val
         | VSigma Val Val
         | VSPair Val Val
         | VCon Label [Val]

           -- Id values
         | VIdP Val Val Val
         | VPath Name Val
         | VComp Val Val (System Val)
         | VTrans Val Val

           -- Neutral values:
         | VVar Ident Val
         | VFst Val
         | VSnd Val
         | VSplit Val Val
         | VApp Val Val
         | VAppFormula Val Formula
  deriving Eq

isNeutral :: Val -> Bool
isNeutral v = case v of
  VVar _ _        -> True
  VFst v          -> isNeutral v
  VSnd v          -> isNeutral v
  VSplit _ v      -> isNeutral v
  VApp v _        -> isNeutral v
  VAppFormula v _ -> isNeutral v
  _               -> False

mkVar :: Int -> Val -> Val
mkVar k = VVar ('X' : show k)

--------------------------------------------------------------------------------
-- | Environments

data Env = Empty
         | Pair Env (Ident,Val)
         | Def [Decl] Env
         | Sub Env (Name,Formula)
  deriving Eq

pairs :: Env -> [(Ident,Val)] -> Env
pairs = foldl Pair

-- lookupIdent :: Ident -> [(Ident,a)] -> Maybe a
-- lookupIdent x defs = listToMaybe [ t | ((y,l),t) <- defs, x == y ]

mapEnv :: (Val -> Val) -> (Formula -> Formula) -> Env -> Env
mapEnv f g e = case e of
  Empty         -> Empty
  Pair e (x,v)  -> Pair (mapEnv f g e) (x,f v)
  Def ts e      -> Def ts (mapEnv f g e)
  Sub e (i,phi) -> Sub (mapEnv f g e) (i,g phi)

valAndFormulaOfEnv :: Env -> ([Val],[Formula])
valAndFormulaOfEnv rho = case rho of
  Empty -> ([],[])
  Pair rho (_,u) -> let (us,phis) = valAndFormulaOfEnv rho
                    in (u:us,phis)
  Sub rho (_,phi) -> let (us,phis) = valAndFormulaOfEnv rho
                     in (us,phi:phis)
  Def _ rho -> valAndFormulaOfEnv rho

valOfEnv :: Env -> [Val]
valOfEnv = fst . valAndFormulaOfEnv

formulaOfEnv :: Env -> [Formula]
formulaOfEnv = snd . valAndFormulaOfEnv

domainEnv :: Env -> [Name]
domainEnv rho = case rho of
  Empty        -> []
  Pair e (x,v) -> domainEnv e
  Def ts e     -> domainEnv e
  Sub e (i,_)  -> i : domainEnv e

--------------------------------------------------------------------------------
-- | Pretty printing

instance Show Env where
  show = render . showEnv

showEnv, showEnv1 :: Env -> Doc
showEnv e = case e of
  Empty           -> PP.empty
  Def _ env       -> showEnv env
  Pair env (x,u)  -> parens (showEnv1 env <> showVal u)
  Sub env (i,phi) -> parens (showEnv1 env <> text (show phi))
showEnv1 (Pair env (x,u)) = showEnv1 env <> showVal u <> text ", "
showEnv1 e                = showEnv e

instance Show Loc where
  show = render . showLoc

showLoc :: Loc -> Doc
showLoc (Loc name (i,j)) = hcat [text name,text "_L",int i,text "_C",int j]

instance Show Ter where
  show = render . showTer

showTer :: Ter -> Doc
showTer v = case v of
  U                -> char 'U'
  App e0 e1        -> showTer e0 <+> showTer1 e1
  Pi e0            -> text "Pi" <+> showTer e0
  Lam x t e        -> char '\\' <> text x <+> text "->" <+> showTer e
  Fst e            -> showTer e <> text ".1"
  Snd e            -> showTer e <> text ".2"
  Sigma e0         -> text "Sigma" <+> showTer e0
  SPair e0 e1      -> parens (showTer1 e0 <> comma <> showTer1 e1)
  Where e d        -> showTer e <+> text "where" <+> showDecls d
  Var x            -> text x
  Con c es         -> text c <+> showTers es
  Split l _ _      -> text "split" <+> showLoc l
  Sum _ n _        -> text "sum" <+> text n
  Undef _          -> text "undefined"
  IdP e0 e1 e2     -> text "IdP" <+> showTers [e0,e1,e2]
  Path i e         -> char '<' <> text (show i) <> char '>' <+> showTer e
  AppFormula e phi -> showTer1 e <> char '@' <> text (show phi)
  Comp e0 e1 es    -> text "comp" <+> showTers [e0,e1] <+> text (showSystem es)
  Trans e0 e1      -> text "transport" <+> showTers [e0,e1]

showTers :: [Ter] -> Doc
showTers = hsep . map showTer1

showTer1 :: Ter -> Doc
showTer1 t = case t of
  U        -> char 'U'
  Con c [] -> text c
  Var x    -> text x
  Split{}  -> showTer t
  Sum{}    -> showTer t
  _        -> parens (showTer t)

showDecls :: [Decl] -> Doc
showDecls defs = hsep $ punctuate comma
                      [ text x <+> equals <+> showTer d | (x,(_,d)) <- defs ]

instance Show Val where
  show = render . showVal

showVal, showVal1 :: Val -> Doc
showVal v = case v of
  VU                -> char 'U'
  Ter t env         -> showTer t <+> showEnv env
  VCon c us         -> text c <+> showVals us
  VPi a b           -> text "Pi" <+> showVals [a,b]
  VSPair u v        -> parens (showVal1 u <> comma <> showVal1 v)
  VSigma u v        -> text "Sigma" <+> showVals [u,v]
  VApp u v          -> showVal u <+> showVal1 v
  VSplit u v        -> showVal u <+> showVal1 v
  VVar x t          -> text x
  VFst u            -> showVal u <> text ".1"
  VSnd u            -> showVal u <> text ".2"
  VIdP v0 v1 v2     -> text "IdP" <+> showVals [v0,v1,v2]
  VPath i v         -> char '<' <> text (show i) <> char '>' <+> showVal v
  VAppFormula v phi -> showVal1 v <> char '@' <> text (show phi)
  VComp v0 v1 vs    -> text "comp" <+> showVals [v0,v1] <+> text (showSystem vs)
  VTrans v0 v1      -> text "trans" <+> showVals [v0,v1]
showVal1 v = case v of
  VU        -> char 'U'
  VCon c [] -> text c
  VVar{}    -> showVal v
  _         -> parens (showVal v)

showVals :: [Val] -> Doc
showVals = hsep . map showVal1

