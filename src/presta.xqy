xquery version "1.0-ml";
(:
 : presta.xqy
 :
 : Copyright (c) 2011-2012 Michael Blakeley. All Rights Reserved.
 :
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 :
 : http://www.apache.org/licenses/LICENSE-2.0
 :
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :
 : The use of the Apache License does not indicate that this project is
 : affiliated with the Apache Software Foundation.
 :
 :)
module namespace p = "com.blakeley.presta" ;

declare default function namespace "http://www.w3.org/2005/xpath-functions" ;

declare namespace xe = "xdmp:eval";

import module namespace cprof = "com.blakeley.cprof" at "cprof.xqy" ;

declare variable $APPKEY as xs:string := xdmp:integer-to-hex(xdmp:server()) ;

declare variable $MODULES-ROOT as xs:string := "com.blakeley.presta/" ;

declare variable $MODULES-DB as xs:unsignedLong := (
  (: Use the selected modules database if it is a database,
   : or else the built-in default.
   :)
  xdmp:modules-database()[. ne 0],
  xdmp:database('Modules'))[1] ;

(: These options are used only for module management :)
declare variable $INSTALL-OPTIONS as element(xe:options) :=
<options xmlns="xdmp:eval">
{
  element database { $MODULES-DB },
  element modules { $MODULES-DB },
  element root { $MODULES-ROOT }
}
</options> ;

(: These options are used for module invoke or spawn :)
declare variable $MODULE-OPTIONS as element(xe:options) :=
<options xmlns="xdmp:eval">
{
  element modules { $MODULES-DB },
  element root { p:path() }
}
</options> ;

declare function p:error(
  $code as xs:string,
  $messages as item()*)
as empty-sequence()
{
  error((), concat('PRESTA-', $code), $messages)
};

declare function p:install($forced as xs:boolean)
as empty-sequence()
{
  (: TODO configurable permissions? probably need a presta role or roles...
   :)
  let $path := concat($MODULES-ROOT, 'store.xqy')
  let $source := text {
    'xquery version "1.0-ml";
    declare variable $FORCED as xs:boolean external;
    declare variable $PATH as xs:string external;
    declare variable $SOURCE as node() external;
    declare variable $ROLES := xdmp:get-current-roles() ;
    if (not($FORCED) and xdmp:exists(doc($PATH))) then ()
    else xdmp:document-insert(
      $PATH, $SOURCE,
      xdmp:permission($ROLES, ("read", "execute", "update")))' }
  return xdmp:eval(
    $source,
    (xs:QName('PATH'), $path,
      xs:QName('SOURCE'), $source,
      xs:QName('FORCED'), $forced),
    $INSTALL-OPTIONS)
};

declare function p:install()
as empty-sequence()
{
  p:install(false())
};

declare function p:modules-directory-delete($path as xs:string)
as empty-sequence()
{
  xdmp:eval(
    'declare variable $PATH external ;
    if (not(xdmp:directory($PATH, "infinity"))) then ()
    else xdmp:directory-delete($PATH)',
    (xs:QName('PATH'), $path),
    $INSTALL-OPTIONS)
};

declare function p:uninstall()
as empty-sequence()
{
  p:modules-directory-delete($MODULES-ROOT)
};

declare function p:appkey()
as xs:string
{
  $APPKEY
};

declare function p:appkey-set($appkey as xs:string)
as empty-sequence()
{
  if (not(ends-with($APPKEY, '/'))) then () else p:error(
    'APPKEY', text { 'app key may not end with "/"', $appkey }),
  if (not(starts-with($APPKEY, '/'))) then () else p:error(
    'APPKEY', text { 'app key may not start with "/"', $appkey }),
  xdmp:set($APPKEY, $appkey)
};

declare function p:path($suffix as xs:string)
as xs:string
{
  concat(
    $MODULES-ROOT, $APPKEY,
    if (starts-with($suffix, '/')) then '' else '/',
    $suffix)
};

declare function p:path()
as xs:string
{
  p:path('')
};

declare function p:forget-all()
{
  (: delete everything under the appkey prefix :)
  p:modules-directory-delete(p:path())
};

declare function p:store(
  $path as xs:string,
  $hash as xs:unsignedLong,
  $source as node(),
  $forced as xs:boolean)
as xs:unsignedLong
{
  $hash,
  (: TODO would be nice to do without the store.xqy module... :)
  xdmp:invoke(
    'store.xqy',
    (xs:QName('PATH'), $path,
      xs:QName('SOURCE'), $source,
      xs:QName('FORCED'), $forced),
    $INSTALL-OPTIONS)
};

declare function p:store(
  $hash as xs:unsignedLong,
  $source as node(),
  $forced as xs:boolean)
as xs:unsignedLong
{
  p:store(
    p:path(xdmp:integer-to-hex($hash)), $hash, $source, $forced)
};

declare function p:prepare(
  $source as item(),
  $forced as xs:boolean)
as xs:unsignedLong
{
  if ($source instance of node()) then p:store(
    xdmp:hash64(xdmp:quote($source)), $source, $forced)
  else p:prepare(text { $source }, $forced)
};

declare function p:prepare(
  $source as item())
as xs:unsignedLong
{
  p:prepare($source, false())
};

declare function p:options-rewrite(
  $options as element(xe:options)?)
{
  if (empty($options)) then $MODULE-OPTIONS
  else element {node-name($options)} {
    $MODULE-OPTIONS/*,
    for $e in $options/* return typeswitch($e)
    case element(xe:modules) return ()
    case element(xe:root) return ()
    default return $e }
};

declare function p:invoke(
  $id as xs:unsignedLong,
  $vars as item()*,
  $options as element(xe:options)?)
as item()*
{
  cprof:invoke(
    xdmp:integer-to-hex($id),
    $vars,
    p:options-rewrite($options))
};

declare function p:invoke(
  $id as xs:unsignedLong,
  $vars as item()*)
as item()*
{
  p:invoke($id, $vars, ())
};

declare function p:invoke(
  $id as xs:unsignedLong)
as item()*
{
  p:invoke($id, (), ())
};

declare function p:xslt-invoke(
  $id as xs:unsignedLong,
  $input as node()?,
  $params as map:map?,
  $options as element(xe:options)?)
as document-node()*
{
  cprof:xslt-invoke(
    xdmp:integer-to-hex($id),
    $input,
    $params,
    p:options-rewrite($options))
};

declare function p:xslt-invoke(
  $id as xs:unsignedLong,
  $input as node()?,
  $params as map:map?)
as document-node()*
{
  p:xslt-invoke($id, $input, $params, ())
};

declare function p:xslt-invoke(
  $id as xs:unsignedLong,
  $input as node()?)
as document-node()*
{
  p:xslt-invoke($id, $input, (), ())
};

declare function p:xslt-invoke(
  $id as xs:unsignedLong)
as document-node()*
{
  p:xslt-invoke($id, (), (), ())
};

(: presta.xqy :)
