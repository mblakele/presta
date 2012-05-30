PRESTA - Prepared Statements and XQuery Module Utilities for MarkLogic Server
===

Prepared Statements and XQuery Module Utilities
---

You are writing an application or a service using MarkLogic Server
later and XQuery (or XSLT). Presta can help with routine tasks:

* code management
* concurrent evaluation
* conditional profiling

Note that some features require MarkLogic Server 5.0 or later.

Installation
---

* Clone this repository
* Copy the `cprof.xqy` and `presta.xqy` files into your module root
* When you want to use presta functionality, import the library module.

    import module namespace presta="com.blakeley.presta"
      at "/path/to/presta.xqy";

If you will use conditional profiling, import cprof too.

    import module namespace presta="com.blakeley.cprof"
      at "/path/to/cprof.xqy";

You can also import `cprof.xqy` without importing `presta.xqy`.

Code Management
---

Presta can manage your XQuery and XSLT code modules for you,
and largely dispenses with the need to specify module storage.
This can be helpful if you want your application to deploy automatically,
but still want the performance benefits of module caching.

Invoking a prepared statement works just like `xdmp:invoke`.

    (: presta:prepare returns an xs:unsignedLong id,
     : which can be used to refer to the prepared statement.
     :)
    let $xqy := '
      declare variable $ID external;
      xdmp:log(text { "hello world!", $ID })'
    let $presta-id := presta:prepare($xqy)
    for $i in 1 to 10
    return presta:invoke(
      $presta-id, (xs:QName('ID'), $i), $invoke-options)

You can also prepare XSL statements with `presta:prepare`.
The caller is responsible for knowing whether a particular Presta id
represents an XQuery module or an XSLT module,
and calling `presta:invoke` or `presta:xslt-invoke` as appropriate.

Your XQuery or XSLT may rely on one or more library modules.
Presta can also manage these.

    presta:library-prepare('lib.xqy', $library-xqy-as-string)

Library module paths are set using the first parameter, and must not conflict.
Calling `presta:library-prepare`
on a library module that already exists will replace it,
if the new XQuery has a different `xdmp:hash64` checksum.

In most cases, repeating `presta:prepare`
will be cheaper that repeating `presta:library-prepare`.
But try to prepare both statements and libraries just once,
when your application is installed or initializes.
Otherwise Presta will do extra work for each call
to `presta:prepare` or `presta:library-prepare`,
and that may become a bottleneck.

To avoid conflicts when multiple applications use Presta in the same cluster,
Presta will automatically generate an application key
based on your current application-server environment.
The current value of the key is available via `presta:appkey`.
If you wish to share the presta cache between appservers,
you can set your own key using `presta:appkey-set`.

This release of Presta sets appropriate defaults for security,
based on the roles held by the user that calls `presta:install`
and `presta:prepare`.
TODO make this configurable? presta role(s)?

TODO

Concurrent Evaluation
---

MarkLogic runs a special Task Server on every host,
which can be used for asynchronous background tasks.
Normally you would write a module and call `xdmp:spawn`
to run it on the Task Server. Presta can manage the module storage for you,
making concurrent evaluation easier.

    (: xdmp:spawn relies on a pre-existing module,
     : so it cannot eval an arbitrary XQuery string.
     :)
    xdmp:spawn('my-module.xqy')

    (: presta:spawn relies on a pre-existing module,
     : so it cannot eval an arbitrary XQuery string.
TODO spawn-eval or eval-concurrent ?
     :)
    presta:spawn-eval('xdmp:log("hello world!")')

TODO discuss return variables, which require ML5 or later

    (: Presta also supports prepared statements,
     : which will be more efficient when the same task
     : runs multiple times.
     :)
    presta:spawn-prepared($presta-id)

If you wish to see the result of your spawned task
returned by any of the `presta:spawn*` functions,
be sure to set `<result>true</result>` in the spawn options.

Like `presta:eval`, `presta:spawn-eval` supports conditional profiling.

TODO

Conditional Profiling
---

Your application uses some combination of
HTTP, `xdmp:eval`, `xdmp:invoke`, `xdmp:value`,
`xdmp:xslt-eval`, and `xdmp:xslt-eval`.
You have discovered a slow request, and you want to profile it.
But adding profiler support to an HTTP request can be tricky.
Changing metaprogramming calls like `xdmp:invoke` to `prof:invoke`
is also tricky: the functions from the
[Profile API](http://developer.marklogic.com/pubs/5.0/apidocs/ProfileBuiltins.html)
return a sequence of the ordinary results, followed by a profile.
This breaks your existing code.

What you want is a way to profile your main request,
and stack up nested evaluation profiles until the end of the query.
Then you can decide what to do with all the profiler output:
display it, log it, email it, etc.

This XQuery library makes that pattern easy. Here is an example:

    import module namespace cprof="com.blakeley.cprof
      at "/path/to/cprof.xqy";

    (: logic to enable profiling :)
    if (not(xs:boolean(xdmp:get-request-field('profile', '0')))) then ()
    else cprof:enable(),

    cprof:eval('xdmp:sleep(5)'),

    (: send the report XML wherever you like :)
    cprof:report()

The only necessary logic is whether or not to call `cprof:enable`.
After that, you can simply replace `xdmp:eval`, `xdmp:invoke`, etc
with `cprof:eval`, `cprof:invoke`, etc.
The function signatures are identical.
You can also use the Presta functions documented above.
At the end of the query, call `cprof:report`
and do whatever you like with the sequence of `prof:report` elements.
If you get back the empty sequence, then profiling was not enabled.

This replaces the older cprof library. Since Presta needed to
integrate conditional profiling, it seemed easiest to merge the two projects.

Note that `cprof:value` is implemented, but will exhibit problems
when the supplied expression relies on the caller's context.
This is because the `xdmp:value` call will be made
from the Presta cprof library module evaluation context.
Thus, `cprof:value` calls cannot rely on variables
or imports that are only available in the caller evaluation context.

    (: this works :)
    cprof:eval('xdmp:sleep(5)')

    (: this throws an error or returns unexpected results :)
    cprof:eval('$my-local-variable')

Note that `cprof:report` takes an optional boolean argument.
If set, the return value will be a single `prof:report` element
with the main request's `prof:metadata` element and with
all of the histograms merged into one `prof:histogram` element.
This may be a little confusing, since the sum of
all the histogram expressions may exceed headline elapsed time.

The functions in this library are lightweight,
so you do not need to disable them for production.

Test Cases
---

The Presta test cases use [XQUT](https://github.com/mblakele/xqut).
If you find problems, please provide a test case.
Patches are welcome.

License
---
Copyright (c) 2011-2012 Michael Blakeley. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

The use of the Apache License does not indicate that this project is
affiliated with the Apache Software Foundation.
