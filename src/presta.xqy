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
declare namespace server-status = "http://marklogic.com/xdmp/status/server";

import module "http://marklogic.com/xdmp/security"
  at "/MarkLogic/security.xqy" ;

import module namespace cprof = "com.blakeley.cprof"
  at "cprof.xqy" ;

declare variable $APPKEY as xs:string := p:appkey-default() ;

declare variable $MODULES-ROOT as xs:string := "com.blakeley.presta/" ;

declare variable $MODULES-DB as xs:unsignedLong := (
  (: Use the selected modules database if it is a database,
   : or else the built-in default.
   :)
  xdmp:modules-database()[. ne 0],
  xdmp:database('Modules'))[1] ;

(: These options are used only for module management :)
declare variable $STORE-OPTIONS as element(xe:options) :=
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

declare function p:error(
  $code as xs:string)
as empty-sequence()
{
  p:error($code, ())
};

declare function p:assert-admin(
  $message as xs:string)
as empty-sequence()
{
  if (xdmp:get-current-roles() = xdmp:role('admin')) then ()
  else p:error(
    'NOTADMIN',
    text { 'This functionality requires the admin role:', $message })
};

declare function p:install-security-amps(
  $amps as element(sec:amp)+ )
 as empty-sequence()
{
  error((), 'UNIMPLEMENTED')
};

declare function p:install-security-collections(
  $collections as element(sec:collection)+ )
 as empty-sequence()
{
  error((), 'UNIMPLEMENTED')
};

declare function p:install-security-permission(
  $permission as element(sec:permission) )
 as element(sec:permission)+
{
  if ($permission/sec:role-id) then $permission
  else xdmp:permission($permission/sec:role-name, $permission/sec:capability)
};

declare function p:install-security-privileges(
  $privileges as element(sec:privilege)+ )
 as empty-sequence()
{
  (: create-privilege returns an id, which we do not use :)
  for $p in $privileges
  let $do := try {
    sec:create-privilege(
      $p/sec:privilege-name, $p/sec:action, $p/sec:kind, $p/sec:role-name) }
  catch ($ex) {
    if (not($ex/error:code = (
          'SEC-PRIVEXISTS', 'SEC-PRIVNAMEEXISTS'))) then xdmp:rethrow()
    else try {
      sec:privilege-set-name(
        $p/sec:action, $p/sec:kind, $p/sec:privilege-name) }
    catch ($ex) {
      (: PRIVNAMEEXISTS? good, nothing to do :)
      if (not($ex/error:code = ('SEC-PRIVNAMEEXISTS'))) then xdmp:rethrow()
      else () },
    sec:privilege-set-roles(
      $p/sec:action,
      $p/sec:kind,
      $p/sec:role-name) }
  return ()
};

declare function p:install-security-roles(
  $roles as element(sec:role)+ )
 as empty-sequence()
{
  (: create-role returns an id, which we do not use :)
  for $r in $roles
  let $do := try {
    sec:create-role(
      $r/sec:role-name,
      ($r/sec:description, $r/sec:role-name)[1],
      $r/sec:role-names/sec:role-name,
      p:install-security-permission($r/sec:permission),
      $r/sec:collection) }
  catch ($ex) {
    if (not($ex/error:code = ('SEC-ROLEEXISTS'))) then xdmp:rethrow()
    else (
      sec:role-set-description(
        $r/sec:role-name, ($r/sec:description, $r/sec:role-name)[1] ),
      sec:role-set-roles(
        $r/sec:role-name, $r/sec:role-names/sec:role-name ),
      sec:role-set-default-permissions(
        $r/sec:role-name, p:install-security-permission($r/sec:permission)),
      sec:role-set-default-collections($r/sec:role-name, $r/sec:collection)) }
  return ()
};

declare function p:install-security-users(
  $users as element(sec:user)+ )
 as empty-sequence()
{
  (: create-user returns an id, which we do not use :)
  for $r in $users
  let $do := try {
    sec:create-user(
      $r/sec:user-name,
      ($r/sec:description, $r/sec:user-name)[1],
      ($r/sec:password, $r/sec:user-name)[1],
      $r/sec:role-name, $r/sec:permission, $r/sec:collection ) }
  catch ($ex) {
    if (not($ex/error:code = ('SEC-USEREXISTS'))) then xdmp:rethrow()
    else (
      sec:user-set-description(
        $r/sec:user-name, ($r/sec:description, $r/sec:user-name)[1]),
      sec:user-set-password(
        $r/sec:user-name, ($r/sec:password, $r/sec:user-name)[1]),
      sec:user-set-roles(
        $r/sec:user-name, $r/sec:role-name ),
      sec:user-set-default-permissions(
        $r/sec:user-name, p:install-security-permission($r/sec:permission)),
      sec:user-set-default-collections($r/sec:user-name, $r/sec:collection)) }
  return ()
};

declare function p:install-security($config as map:map)
as empty-sequence()
{
  p:assert-admin('install-security'),
  if (xdmp:security-database() eq xdmp:database()) then ()
  else error(
    (), 'INSTALL-NOTSECURITY', text {
      xdmp:database-name(xdmp:database()), 'is not the Security database' })
  ,
  for $key in map:keys($config)
  let $assert := (
    if ($key = (
        'amps', 'collections', 'privileges', 'roles', 'users')) then ()
    else p:error('UNEXPECTED', $key))
  return xdmp:apply(
    xdmp:function(xs:QName(concat('p:install-security-', $key))),
    map:get($config, $key))
};

(: Bootstrap the Presta environment.
 : This must run as the admin user.
 :)
declare function p:install($forced as xs:boolean)
as empty-sequence()
{
  p:assert-admin('install'),

  (: security - part I :)
  let $config := map:map()
  let $put := map:put(
    $config, 'roles',
    element sec:role { element sec:role-name { 'presta' } })
  return cprof:eval(
    'xquery version "1.0-ml";
     import module namespace p = "com.blakeley.presta" at "presta.xqy";
     declare option xdmp:update "true";
     declare variable $CONFIG external;
     p:install-security($CONFIG)',
    (xs:QName('CONFIG'), $config),
    <options xmlns="xdmp:eval">
      <database>{ xdmp:security-database() }</database>
      <isolation>different-transaction</isolation>
    </options>),

  (: security - part II :)
  let $config := map:map()
  let $put := map:put(
    $config, 'roles',
    (element sec:role {
        element sec:role-name { 'presta' },
        element sec:permission {
          element sec:role-name { 'presta' },
          for $c in ('execute', 'insert', 'read', 'update')
          return element sec:capability { $c } } }))
  let $put := map:put(
    $config, 'privileges',
    (for $p in (
        'xdmp-invoke', 'xdmp-invoke-in', 'xdmp-invoke-modules-change')
      return element sec:privilege {
        element sec:privilege-name { replace($p, '^xdmp-', 'xdmp:') },
        element sec:action {
          concat('http://marklogic.com/xdmp/privileges/', $p) },
        element sec:kind { 'execute' },
        element sec:role-name { 'presta' } },
      (: URI privilege for module storage :)
      element sec:privilege {
        element sec:privilege-name { 'presta-modules-root' },
        element sec:action { $MODULES-ROOT },
        element sec:kind { 'uri' },
        element sec:role-name { 'presta' } }))
  return cprof:eval(
    'xquery version "1.0-ml";
     import module namespace p = "com.blakeley.presta" at "presta.xqy";
     declare option xdmp:update "true";
     declare variable $CONFIG as map:map external ;
     p:install-security($CONFIG)',
    (xs:QName('CONFIG'), $config),
    <options xmlns="xdmp:eval">
      <database>{ xdmp:security-database() }</database>
      <isolation>different-transaction</isolation>
    </options>),

  (: modules :)
  let $path := concat($MODULES-ROOT, 'store.xqy')
  (: Unless forced, this module will never override hashed paths,
   : which are XQuery main modules or XSLT stylesheets.
   : Unless forced, it will check the hash of library modules.
   : Because this module runs in update mode,
   : it must test with fn:exists rather than xdmp:exists.
   : This forces a lock.
   :)
  let $source := text {
    'xquery version "1.0-ml";
    declare variable $FORCED as xs:boolean external;
    declare variable $HASH as xs:unsignedLong external;
    declare variable $PATH as xs:string external;
    declare variable $SOURCE as node() external;
    if (not($FORCED)
      and exists(doc($PATH))
      and (ends-with($PATH, concat("/", $HASH))
        or xdmp:hash64(doc($PATH)) eq $HASH)) then ()
    else xdmp:document-insert(
      $PATH, $SOURCE,
      xdmp:permission(
        xdmp:role("presta"), ("execute", "insert", "read", "update")))' }
  return cprof:eval(
    $source,
    (xs:QName('FORCED'), $forced,
      xs:QName('HASH'), xdmp:hash64($source),
      xs:QName('PATH'), $path,
      xs:QName('SOURCE'), $source),
    $STORE-OPTIONS)
};

declare function p:install()
as empty-sequence()
{
  p:install(false())
};

declare function p:module-delete($path as xs:string)
as empty-sequence()
{
  cprof:eval(
    'declare variable $PATH external ;
    if (not(doc($PATH))) then () else xdmp:document-delete($PATH)',
    (xs:QName('PATH'), $path),
    $STORE-OPTIONS)
};

declare function p:modules-directory-delete($path as xs:string)
as empty-sequence()
{
  cprof:eval(
    'declare variable $PATH external ;
    if (not(xdmp:directory($PATH, "infinity"))) then ()
    else xdmp:directory-delete($PATH)',
    (xs:QName('PATH'), $path),
    $STORE-OPTIONS)
};

declare function p:uninstall-security-privileges()
as empty-sequence()
{
  p:assert-admin('uninstall-security'),
  if (xdmp:security-database() eq xdmp:database()) then ()
  else error(
    (), 'INSTALL-NOTSECURITY', text {
      xdmp:database-name(xdmp:database()), 'is not the Security database' }),
  try { sec:remove-privilege($MODULES-ROOT, 'uri') }
  catch ($ex) {
    if (not($ex/error:code = ('SEC-PRIVDNE'))) then xdmp:rethrow()
    else () }
};

declare function p:uninstall-security-roles()
as empty-sequence()
{
  p:assert-admin('uninstall-security'),
  if (xdmp:security-database() eq xdmp:database()) then ()
  else error(
    (), 'INSTALL-NOTSECURITY', text {
      xdmp:database-name(xdmp:database()), 'is not the Security database' }),
  try { sec:remove-role('presta') }
  catch ($ex) {
    if (not($ex/error:code = ('SEC-ROLEDNE'))) then xdmp:rethrow()
    else () }
};

declare function p:uninstall()
as empty-sequence()
{
  p:assert-admin('uninstall'),
  p:modules-directory-delete($MODULES-ROOT),
  cprof:eval(
    'xquery version "1.0-ml";
     import module namespace p = "com.blakeley.presta" at "presta.xqy";
     p:uninstall-security-privileges() ;
     xquery version "1.0-ml";
     import module namespace p = "com.blakeley.presta" at "presta.xqy";
     p:uninstall-security-roles()',
    (),
    <options xmlns="xdmp:eval">
      <database>{ xdmp:security-database() }</database>
      <isolation>different-transaction</isolation>
    </options>)
};

declare function p:appkey()
as xs:string
{
  $APPKEY
};

declare function p:appkey-default()
as xs:string
{
  xdmp:integer-to-hex(xdmp:server())
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

declare function p:forget(
  $id as xs:unsignedLong)
{
  (: delete a single module :)
  p:module-delete(p:path(xdmp:integer-to-hex($id)))
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
  cprof:invoke(
    'store.xqy',
    (xs:QName('FORCED'), $forced,
      xs:QName('HASH'), $hash,
      xs:QName('PATH'), $path,
      xs:QName('SOURCE'), $source),
    $STORE-OPTIONS)
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

declare function p:import(
  $path as xs:string,
  $source as xs:string,
  $forced as xs:boolean)
as empty-sequence()
{
  p:store(
    p:path($path), xdmp:hash64($source), text { $source }, $forced)[0]
};

declare function p:import(
  $path as xs:string,
  $source as xs:string)
as empty-sequence()
{
  p:import($path, $source, false())
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

declare function p:spawn(
  $id as xs:unsignedLong,
  $vars as item()*,
  $options as element(xe:options)?,
  $retry as xs:integer)
as item()*
{
  (: There is no prof:spawn, hence no cprof:spawn :)
  if (not($retry)) then xdmp:spawn(
    xdmp:integer-to-hex($id),
    $vars,
    p:options-rewrite($options))
  else if (xdmp:server-status(xdmp:host(),xdmp:server("TaskServer"))/server-status:queue-size[. lt ../server-status:queue-limit])
  then
    xdmp:spawn(
      xdmp:integer-to-hex($id),
      $vars,
      p:options-rewrite($options))
  else
    (xdmp:sleep($retry),
    p:spawn($id, $vars, $options, 2 * $retry) )
};

declare function p:spawn(
  $id as xs:unsignedLong,
  $vars as item()*,
  $options as element(xe:options)?)
as item()*
{
  p:spawn($id, $vars, $options, 0)
};

declare function p:spawn(
  $id as xs:unsignedLong,
  $vars as item()*)
as item()*
{
  p:spawn($id, $vars, ())
};

declare function p:spawn(
  $id as xs:unsignedLong)
as item()*
{
  p:spawn($id, (), ())
};

(: presta.xqy :)
