{-
    BNF Converter: Bison generator
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{-
    BNF Converter: C++ Bison generator
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{-
   **************************************************************
    BNF Converter Module

    Description   : This module generates the Bison input file.
                    Note that because of the way bison stores results
                    the programmer can increase performance by limiting
                    the number of entry points in their grammar.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 6 August, 2003

    Modified      : 6 August, 2003


   **************************************************************
-}


module BNFC.Backend.CPP.NoSTL.CFtoBison (cf2Bison) where

import BNFC.CF
import Data.List (intersperse)
import BNFC.Backend.Common.NamedVariables hiding (varName)
import BNFC.Backend.CPP.STL.CFtoBisonSTL (union)
import Data.Char (toLower,isUpper)
import BNFC.Utils ((+++))
import BNFC.TypeChecker
import ErrM
import BNFC.Backend.C.CFtoBisonC (startSymbol)
import BNFC.PrettyPrint

--This follows the basic structure of CFtoHappy.

-- Type declarations
type Rules       = [(NonTerminal,[(Pattern,Action)])]
type Pattern     = String
type Action      = String
type MetaVar     = String

--The environment comes from the CFtoFlex
cf2Bison :: String -> CF -> SymEnv -> String
cf2Bison name cf env
 = unlines
    [header name cf,
     render $ union Nothing (allCats cf),
     "%token _ERROR_",
     tokens user env,
     declarations cf,
     startSymbol cf,
     specialToks cf,
     "%%",
     prRules (rulesForBison name cf env)
    ]
  where
   user = fst (unzip (tokenPragmas cf))

header :: String -> CF -> String
header name cf = unlines
    [ "/* This Bison file was machine-generated by BNFC */"
    , "%{"
    , "#include <stdlib.h>"
    , "#include <stdio.h>"
    , "#include <string.h>"
    , "#include \"Absyn.H\""
    , "int yyparse(void);"
    , "int yylex(void);"
    , "int yy_mylinenumber;"  --- hack to get line number. AR 2006
    , "int initialize_lexer(FILE * inp);"
    , "int yywrap(void)"
    , "{"
    , "  return 1;"
    , "}"
    , "void yyerror(const char *str)"
    , "{"
    , "  extern char *yytext;"
    , "  fprintf(stderr,\"error: line %d: %s at %s\\n\", "
    , "    yy_mylinenumber + 1, str, yytext);"
    , "}"
    , ""
    , definedRules cf
    , unlines $ map (parseMethod name) (allCatsNorm cf)  -- (allEntryPoints cf), M.F. 2004-09-14 fix of [Ty2] bug.
    , concatMap reverseList (filter isList (allCatsNorm cf))
    , "%}"
    ]

definedRules :: CF -> String
definedRules cf = unlines [ rule f xs e | FunDef f xs e <- cfgPragmas cf]
  where
    ctx = buildContext cf

    list = LC (const "[]") (\ t -> "List" ++ unBase t)
      where
        unBase (ListT t) = unBase t
        unBase (BaseT x) = show$normCat$strToCat x

    rule f xs e =
        case checkDefinition' list ctx f xs e of
            Bad err -> error $ "Panic! This should have been caught already:\n" ++ err
            Ok (args,(e',t)) -> unlines
                [ cppType t ++ " " ++ f ++ "_ (" ++
                  concat (intersperse ", " $ map cppArg args) ++ ") {"
                , "  return " ++ cppExp e' ++ ";"
                , "}"
                ]
      where
        cppType :: Base -> String
        cppType (ListT (BaseT x)) = "List" ++ show (normCat (strToCat x)) ++ " *"
        cppType (ListT t) = cppType t ++ " *"
        cppType (BaseT x)
            | isToken x ctx = "String"
            | otherwise = show (normCat (strToCat x)) ++ " *"

        cppArg :: (String, Base) -> String
        cppArg (x,t) = cppType t ++ " " ++ x ++ "_"

        cppExp :: Exp -> String
        cppExp (App "[]" []) = "0"
        cppExp (App x [])
            | elem x xs = x ++ "_"  -- argument
        cppExp (App t [e])
            | isToken t ctx = cppExp e
        cppExp (App x es)
            | isUpper (head x) = call ("new " ++ x) es
            | otherwise = call (x ++ "_") es
        cppExp (LitInt n) = show n
        cppExp (LitDouble x) = show x
        cppExp (LitChar c) = show c
        cppExp (LitString s) = show s

        call x es = x ++ "(" ++ concat (intersperse ", " $ map cppExp es) ++ ")"


--This generates a parser method for each entry point.
parseMethod :: String -> Cat -> String
parseMethod _ cat =
  -- if normCat cat /= cat     M.F. 2004-09-17 comment. No duplicates from allCatsIdNorm
  -- then ""
  -- else
  unlines
  [
   cat' ++ "*" +++ (resultName cat') +++ "= 0;",
   cat' ++"* p" ++ cat' ++ "(FILE *inp)",
   "{",
   "  initialize_lexer(inp);",
   "  if (yyparse())",
   "  { /* Failure */",
   "    return 0;",
   "  }",
   "  else",
   "  { /* Success */",
   "    return" +++ (resultName cat') ++ ";",
   "  }",
   "}"
  ]
 where
  cat' = identCat (normCat cat)

--This method generates list reversal functions for each list type.
reverseList :: Cat -> String
reverseList c = unlines
 [
  c' ++ "* reverse" ++ c' ++ "(" ++ c' +++ "*l)",
  "{",
  "  " ++ c' +++"*prev = 0;",
  "  " ++ c' +++"*tmp = 0;",
  "  while (l)",
  "  {",
  "    tmp = l->" ++ v ++ ";",
  "    l->" ++ v +++ "= prev;",
  "    prev = l;",
  "    l = tmp;",
  "  }",
  "  return prev;",
  "}"
 ]
 where
  c' = identCat (normCat c)
  v = (map toLower c') ++ "_"

--declares non-terminal types.
declarations :: CF -> String
declarations cf = concatMap (typeNT cf) (allCats cf)
 where --don't define internal rules
   typeNT cf nt | rulesForCat cf nt /= [] = "%type <" ++ varName nt ++ "> " ++ identCat nt ++ "\n"
   typeNT _ _ = ""

--declares terminal types.
tokens :: [UserDef] -> SymEnv -> String
tokens user ts = concatMap (declTok user) ts
 where
  declTok u (s,r) = if elem s (map show u)
    then "%token<string_> " ++ r ++ "    //   " ++ s ++ "\n"
    else "%token " ++ r ++ "    //   " ++ s ++ "\n"

specialToks :: CF -> String
specialToks cf = concat [
  ifC catString "%token<string_> _STRING_\n",
  ifC catChar "%token<char_> _CHAR_\n",
  ifC catInteger "%token<int_> _INTEGER_\n",
  ifC catDouble "%token<double_> _DOUBLE_\n",
  ifC catIdent "%token<string_> _IDENT_\n"
  ]
   where
    ifC cat s = if isUsedCat cf cat then s else ""

--The following functions are a (relatively) straightforward translation
--of the ones in CFtoHappy.hs
rulesForBison :: String -> CF -> SymEnv -> Rules
rulesForBison _ cf env = map mkOne $ ruleGroups cf where
  mkOne (cat,rules) = constructRule cf env rules cat

-- For every non-terminal, we construct a set of rules.
constructRule :: CF -> SymEnv -> [Rule] -> NonTerminal -> (NonTerminal,[(Pattern,Action)])
constructRule cf env rules nt = (nt,[(p,(generateAction (ruleName r) b m) +++ result) |
     r0 <- rules,
     let (b,r) = if isConsFun (funRule r0) && elem (valCat r0) revs
                   then (True,revSepListRule r0)
                 else (False,r0),
     let (p,m) = generatePatterns cf env r])
 where
   ruleName r = case funRule r of
     "(:)" -> identCat (normCat nt)
     "(:[])" -> identCat (normCat nt)
     z -> z
   revs = cfgReversibleCats cf
   eps = allEntryPoints cf
   isEntry nt = if elem nt eps then True else False
   result = if isEntry nt then (resultName (identCat (normCat nt))) ++ "= $$;" else ""

-- Generates a string containing the semantic action.
generateAction :: Fun -> Bool -> [MetaVar] -> Action
generateAction f b ms =
  if isCoercion f
  then (unwords ms) ++ ";"
  else if f == "[]"
  then "0;"
  else if isDefinedRule f
  then concat [ f, "_", "(", concat $ intersperse ", " ms', ");" ]
  else concat ["new ", f, "(", (concat (intersperse ", " ms')), ");"]
 where
  ms' = if b then reverse ms else ms

-- Generate patterns and a set of metavariables indicating
-- where in the pattern the non-terminal
generatePatterns :: CF -> SymEnv -> Rule -> (Pattern,[MetaVar])
generatePatterns cf env r = case rhsRule r of
  []  -> ("/* empty */",[])
  its -> (unwords (map mkIt its), metas its)
 where
   mkIt i = case i of
     Left c -> case lookup (show c) env of
       Just x -> x
       Nothing -> typeName (identCat c)
     Right s -> case lookup s env of
       Just x -> x
       Nothing -> s
   metas its = [revIf c ('$': show i) | (i,Left c) <- zip [1 :: Int ..] its]
   revIf c m = if (not (isConsFun (funRule r)) && elem c revs)
                 then ("reverse" ++ (identCat (normCat c)) ++ "(" ++ m ++ ")")
               else m  -- no reversal in the left-recursive Cons rule itself
   revs = cfgReversibleCats cf

-- We have now constructed the patterns and actions,
-- so the only thing left is to merge them into one string.

prRules :: Rules -> String
prRules [] = []
prRules ((_, []):rs) = prRules rs --internal rule
prRules ((nt,((p,a):ls)):rs) =
  (unwords [nt', ":" , p, "{ $$ =", a, "}", "\n" ++ pr ls]) ++ ";\n" ++ prRules rs
 where
  nt' = identCat nt
  pr []           = []
  pr ((p,a):ls)   = (unlines [(concat $ intersperse " " ["  |", p, "{ $$ =", a , "}"])]) ++ pr ls

--Some helper functions.
resultName :: String -> String
resultName s = "YY_RESULT_" ++ s ++ "_"

--slightly stronger than the NamedVariable version.
varName :: Cat -> String
varName = (++ "_") . map toLower . identCat . normCat

typeName :: String -> String
typeName "Ident" = "_IDENT_"
typeName "String" = "_STRING_"
typeName "Char" = "_CHAR_"
typeName "Integer" = "_INTEGER_"
typeName "Double" = "_DOUBLE_"
typeName x = x
