# Bundler analysis with Delfos


So we want to analyse [bundler](http://bundler.io/) with
[Delfos](https://github.com/ruby-analysis/delfos).

Delfos allows us to record runtime type information and call sites and call
stacks for later analysis in a [neo4j](https://neo4j.com/) graph database. You
can also write [custom (non-neo4j) loggers](https://github.com/ruby-analysis/delfos).

Ruby is great for its ease of development, but as an application grows, the
ability to understand a really huge application starts to dwindle.

- You don't have static analysis tools that enable easy refactoring.
- Most applications don't really break apart code into separate packages.
- As the project grows each directory grows with the complexity of the project and number of features.

You may have seen a Rails app with hundreds of models and controllers, and a
folder for every other design pattern under the sun.

With tests, we can tend to refactor with a degree of confidence, but often it
can be difficult to truly know
- what code is still used
- by who
- for what purpose
- and in what context

With Delfos we can start to answer these questions on large ruby projects.

Well it would be nice to use open source software to improve the open source software we use everyday.
What are some of the things we may hope to find.

## What do we hope to gain?
By having runtime information and call stacks, we can find out more about our code than we
typically can with other static analysis tools.

Code issues highlighted by knowing types at runtime:

- Cyclic dependencies
  - in single execution chains
  - at all between two classes (even within separate execution chains/contexts)
  - between different classes in two modules
- Code in one module and directory heavily coupled to another far away module and directory
- Heavily coupled classes that are candidates for unifying:
  - completely
  - certain methods into one object, and others into another object
- A class/classes that stand(s) out as belonging in another module
- Feature envy
  - multiple calls to the same object within the same method
  - multiple calls to the same object within the same execution chain (but different methods)
- Code that is colocated, but completely unrelated. I.e. should be in a different module/directory.


## Let's get started

OK so we want to run the analysis on bundler.
We fork the bundler repo to [https://github.com/ruby-analysis/delfos)(https://github.com/ruby-analysis/delfos).

Then we need to enable `Delfos`

Bundler is a bit of a complex example to begin with, as for the sanity
of the bundler developers, they decided not to use bundler itself to manage
its own dependencies.

In your application or gem (unless it's a competing package manager) you won't
need to deal with this complexity and should be able to just add `gem 'delfos'`
to your Gemfile.

We're currently using delfos locally gem so the path is relative.

```ruby
$:.unshift File.expand_path("../../../delfos/lib", __FILE__)
```

Normal `Delfos` setup:

```ruby
# in spec_helper.rb
Delfos.setup! application_directories: "lib", offline_query_saving: true
```

Note the `offline_query_saving` parameter. This means that during execution of the
bundler test suite, we just persist the raw query parameters to disk instead of
trying to write every query 'live' to neo4j.

The default behaviour is 'live' and you can probably get away with this for small test suites and
for ordinary usage clicking around an app in development mode.


# Recording the data

Now we run the tests for bundler it is slightly unusual:

```
bundler rake spec:deps
```

Then

```
bundler rake spec
```

This will take a while - around 30 minutes vs 17 minutes for a non `Delfos` run on my machine.

It will output a file called `delfos_query_parameters.json`

For bundler this file was 57M

```
-rw-r--r--   1 markburns  staff    57M 21 Jun 18:18 delfos_query_parameters.json
```

The file contents are actually lines of `json`, one query per line.
The bundler output looks like this:

```json
{"step_number":1,"stack_uuid":"52083c51-375a-4f7c-a64a-349cb1fa82f5","call_site_file":"lib/bundler/errors.rb","call_site_line_number":19,"container_method_klass_name":"Bundler::GemfileError","container_method_type":"ClassMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":"Bundler::GemfileError","called_method_type":"ClassMethod","called_method_name":"status_code","called_method_file":"lib/bundler/errors.rb","called_method_line_number":4}
{"step_number":2,"stack_uuid":"52083c51-375a-4f7c-a64a-349cb1fa82f5","call_site_file":"lib/bundler/errors.rb","call_site_line_number":6,"container_method_klass_name":"Bundler::GemfileError","container_method_type":"ClassMethod","container_method_name":"status_code","container_method_file":"lib/bundler/errors.rb","container_method_line_number":4,"called_method_klass_name":"Bundler::BundlerError","called_method_type":"ClassMethod","called_method_name":"all_errors","called_method_file":"lib/bundler/errors.rb","called_method_line_number":14}
{"step_number":3,"stack_uuid":"52083c51-375a-4f7c-a64a-349cb1fa82f5","call_site_file":"lib/bundler/errors.rb","call_site_line_number":11,"container_method_klass_name":"Bundler::GemfileError","container_method_type":"ClassMethod","container_method_name":"status_code","container_method_file":"lib/bundler/errors.rb","container_method_line_number":4,"called_method_klass_name":"Bundler::BundlerError","called_method_type":"ClassMethod","called_method_name":"all_errors","called_method_file":"lib/bundler/errors.rb","called_method_line_number":14}
{"step_number":1,"stack_uuid":"e630eaa5-64dd-49e1-b956-b7503dfb1a09","call_site_file":"lib/bundler/errors.rb","call_site_line_number":20,"container_method_klass_name":"Bundler::InstallError","container_method_type":"ClassMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":"Bundler::InstallError","called_method_type":"ClassMethod","called_method_name":"status_code","called_method_file":"lib/bundler/errors.rb","called_method_line_number":4}
```

This actually represents the params that will be passed to a neo4j query.

## Neo4j Queries
We haven't imported the data yet, but first let's have a look at it.

Here's what the first query would look like:

```cypher
(CallStack{uuid: "52083c51-375a-4f7c-a64a-349cb1fa82f5"})
   -[:STEP{number: 1}]->
   (call_site:CallSite{file:"lib/bundler/errors.rb","line_number":19})

(Class{name:"Bundler::GemfileError"})
  -[:OWNS]->
  (container_method:Method{type:"ClassMethod","name":"(main)","file":null,"line_number":-1})
  -[:CONTAINS]->
  (call_site)

(Class{name:"Bundler::GemfileError"})
  -[:OWNS]->
  (called_method:Method{type:"ClassMethod","name":"status_code","file":"lib/bundler/errors.rb","line_number":4})

(call_site)-[:CALLS]->(called_method)
```

It's maybe a bit overwhelming, if you've not looked at neo4j before so
let's hide the attributes and variable names.

Neo4j cypher syntax is basically `(node) -[:relationship]-> (another_node)`

```cypher
(CallStack) -[:STEP]-> (CallSite)

(Class) -[:OWNS]-> (Method) -[:CONTAINS]-> (CallSite)

(Class) -[:OWNS]-> (Method)

(CallSite)-[:CALLS]->(Method)
```


We can reorder this query like this:

```cypher
(CallStack) -[:STEP]->
  (CallSite) <-[:CONTAINS]-
  (Method) <-[:OWNS]- (Class)

(Class) -[:OWNS]-> (Method) <-[:CALLS]- (CallSite)
```

So trying to read this out we have:

`(CallStack) -[:STEP]-> (CallSite)`

A `CallStack` has a `STEP` to a `CallSite`.

This represents our ordinary chain of execution.

Reading backwards now, we have:

`(Class) -[:OWNS]-> (Method) -[:CONTAINS]-> (CallSite)`

A `Class` which `OWNS` a `Method` which `CONTAINS` the `CallSite`

Then we have:

`(Class) -[:OWNS]-> (Method)`

Another `Class` which `OWNS` another `Method`.

`(Method) <-[:CALLS]- (CallSite)`

The `CallSite` `CALLS` this `Method`.

In summary we have three things which represent code we care about:
- A container `Method` in a file with a line number which belongs to a `Class`
- A `CallSite` with a file and line number
- A called `Method` with file and line number that belongs to another class.

We also have some temporal information recorded which is the sequence
of `CallSite`s that are linked together in numbered `STEP`s from a `CallStack` node.

# Let's import!

OK so now we know a bit about the data we'll be importing, let's get started.

Delfos comes with an executable for turning these persisted parameters into their
corresponding neo4j queries and importing them.

What it does is splits the files up into batches of 10,000 queries each.
Then it goes through line by line and does a synchronous query for each line.
It's currently dumb like that, but it should be possible to use the
neo4j batching feature to speed this up. Or to import from CSV.

It copies the query, splits and saves the split files into `./tmp/delfos`



```
wc tmp/delfos/*
   10000   10000 5746504 tmp/delfos/delfos_queries_aa
   10000   10000 5663845 tmp/delfos/delfos_queries_ab
   10000   10000 5996632 tmp/delfos/delfos_queries_ac
   10000   10000 5705559 tmp/delfos/delfos_queries_ad
   10000   10000 5640383 tmp/delfos/delfos_queries_ae
   10000   10000 5562988 tmp/delfos/delfos_queries_af
   10000   10000 5649757 tmp/delfos/delfos_queries_ag
   10000   10000 5679713 tmp/delfos/delfos_queries_ah
   10000   10000 5626094 tmp/delfos/delfos_queries_ai
   10000   10000 5849289 tmp/delfos/delfos_queries_aj
    4334    4334 2403131 tmp/delfos/delfos_queries_ak
  104334  104334 59523895 tmp/delfos/delfos_query_output.cypher
```

Then it runs an import command on each file.
It persists any errors to `<filename>.errors`

Let's do it now, you'll need a live instance of neo4j running.
Let's install with [ineo](https://github.com/cohesivestack/ineo#installation)

```
curl -sSL http://getineo.cohesivestack.com | bash -s install
source ~/.bashrc
ineo create bundler
ineo set-port bundler 8001
  The http port was successfully changed to '8001'.
```

Now let's start it. Note we chose port `8001`. It's good to have a habit of
being explicit about the neo4j instance, as it can be easy to wipe out
important data accidentally. With that in mind, I never use the default
port `7474`. And in fact, `Delfos` defaults to `7476` just to avoid
non explicit re-use of the same database.

So we start neo4j

```
ineo start bundler
```

Then we run the import

```
NEO4J_PORT=8001 delfos_import
```

So the first run has completed successfully and we got 13 errors.

```
wc tmp/delfos/*
   10000   10000 5746504 tmp/delfos/delfos_queries_aa
   10000   10000 5663845 tmp/delfos/delfos_queries_ab
      13     182    8437 tmp/delfos/delfos_queries_ab.errors
   10000   10000 5996632 tmp/delfos/delfos_queries_ac
   10000   10000 5705559 tmp/delfos/delfos_queries_ad
   10000   10000 5640383 tmp/delfos/delfos_queries_ae
   10000   10000 5562988 tmp/delfos/delfos_queries_af
   10000   10000 5649757 tmp/delfos/delfos_queries_ag
   10000   10000 5679713 tmp/delfos/delfos_queries_ah
   10000   10000 5626094 tmp/delfos/delfos_queries_ai
   10000   10000 5849289 tmp/delfos/delfos_queries_aj
    4334    4334 2403131 tmp/delfos/delfos_queries_ak
  104334  104334 59523895 tmp/delfos/delfos_query_output.cypher
  208681  208850 119056227 total
```

So 13 errors out of 104,334 queries.
99.988% success rate. Not bad.

What do they look like?

```json
{"step_number":1,"stack_uuid":"7b5a17fa-8abc-4dda-854b-a251b4d2593a","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::Attributes","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"810ec287-64bd-4241-9924-ff5f958f62e5","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::Attributes","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"4a10721e-9e9c-45bc-8020-074cde381a8d","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::PostInstall","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"9202c5aa-900b-4132-a002-4a13a3b16679","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":33,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::PostInstall","container_method_type":"InstanceMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"post_install","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":99}
{"step_number":1,"stack_uuid":"26616c53-4bea-4fbd-b585-9ca6d760228d","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::InstallPath","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"9734b37d-6b93-45b8-860d-a31fa5512d46","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":48,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::InstallPath","container_method_type":"InstanceMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"install_path","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":108}
{"step_number":2,"stack_uuid":"9734b37d-6b93-45b8-860d-a31fa5512d46","call_site_file":"lib/bundler/plugin/api/source.rb","call_site_line_number":113,"container_method_klass_name":null,"container_method_type":"InstanceMethod","container_method_name":"install_path","container_method_file":"lib/bundler/plugin/api/source.rb","container_method_line_number":108,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"gem_install_dir","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":278}
{"step_number":1,"stack_uuid":"4d91f4df-7ab1-46e4-bb94-beee27ab6aaa","call_site_file":"lib/bundler/plugin/api/source.rb","call_site_line_number":113,"container_method_klass_name":null,"container_method_type":"InstanceMethod","container_method_name":"install_path","container_method_file":"lib/bundler/plugin/api/source.rb","container_method_line_number":108,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"uri_hash","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":273}
{"step_number":1,"stack_uuid":"0a41f5e3-9110-4143-9145-c810610d45ef","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::ToLock","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"527f3ef7-636e-4292-8e70-d7a0cbee4014","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":61,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::ToLock","container_method_type":"InstanceMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"to_lock","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":254}
{"step_number":2,"stack_uuid":"527f3ef7-636e-4292-8e70-d7a0cbee4014","call_site_file":"lib/bundler/plugin/api/source.rb","call_site_line_number":258,"container_method_klass_name":null,"container_method_type":"InstanceMethod","container_method_name":"to_lock","container_method_file":"lib/bundler/plugin/api/source.rb","container_method_line_number":254,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"options_to_lock","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":74}
{"step_number":1,"stack_uuid":"400c05ce-7108-46d0-9ae8-f2d8a8c19683","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":10,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::ToLock::WithAdditionalOptionsToLock","container_method_type":"InstanceMethod","container_method_name":"source","container_method_file":"/Users/markburns/.rbenv/versions/2.3.3/lib/ruby/gems/2.3.0/gems/rspec-core-3.5.4/lib/rspec/core/memoized_helpers.rb","container_method_line_number":295,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"initialize","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":47}
{"step_number":1,"stack_uuid":"80dfd309-eb42-4ceb-aa85-8c3d6d137954","call_site_file":"spec/bundler/plugin/api/source_spec.rb","call_site_line_number":78,"container_method_klass_name":"RSpec::ExampleGroups::BundlerPluginAPISource::ToLock::WithAdditionalOptionsToLock","container_method_type":"InstanceMethod","container_method_name":"(main)","container_method_file":null,"container_method_line_number":-1,"called_method_klass_name":null,"called_method_type":"InstanceMethod","called_method_name":"to_lock","called_method_file":"lib/bundler/plugin/api/source.rb","called_method_line_number":254}
```

So it's [something to look at](https://github.com/ruby-analysis/delfos/issues/31), a few missing steps.

But for now, we'll continue with the analysis.

## Analysis

So back to our original list of things to look for:


- Cyclic dependencies
  - in single execution chains
  - at all between two classes (even within separate execution chains/contexts)
  - between different classes in two modules
- Code in one module and directory heavily coupled to another far away module and directory
- Heavily coupled classes that are candidates for unifying:
  - completely
  - certain methods into one object, and others into another object
- A class/classes that stand(s) out as belonging in another module
- Feature envy
  - multiple calls to the same object within the same method
  - multiple calls to the same object within the same execution chain (but different methods)
- Code that is colocated, but completely unrelated. I.e. should be in a different module/directory.


# 1. Cyclic dependencies

First one. Cyclic dependencies.

So we want a
`Class` that `OWNS` a `Method`
that `CONTAINS` a `CallSite` that `Calls` another `Method`
that contains another `CallSite` that calls a `Method` that the original
`Class` `OWNS`. Phew!

It's a bit awkward phrasing like that, but I find it helps me build queries.

So what does that look like?

Well we can browse to [http://localhost:8001](http://localhost:8001) and interact with the console.

Here's the query

```cypher
MATCH (c1:Class)-[:OWNS]->(m1:Method)
  -[:CONTAINS]->(cs1:CallSite)-[:CALLS]->(m2:Method)
  -[:CONTAINS]->(cs2:CallSite)-[:CALLS]->(m3:Method)
  <-[:OWNS]-(c1)

RETURN c1, m1, cs1, m2, cs2, m3
LIMIT 1
```

![Non cyclic dependency example](same-class-method-call.svg)

We get results for method calls in the same class!
That's not what we want.

OK so let's ensure we get a call to one class, then back to the original class.
We do this by asserting the names of `c1` and `c2` are not equal with
`WHERE c2.name <> c1.name`.

The first few queries returned less interesting results where the code
was error handling code, so I've also excluded those.

```cypher
MATCH (c1:Class)-[o:OWNS]->(m1:Method)
  -[con1:CONTAINS]->(cs1:CallSite)-[call1:CALLS]->(m2:Method)
  -[con2:CONTAINS]->(cs2:CallSite)-[call2:CALLS]->(m3:Method)
  <-[o2:OWNS]-(c1),
(c2:Class)-[o3:OWNS]->(m2)

WHERE c2.name <> c1.name
  AND c1.name <> "Bundler::BundlerError"
  AND c2.name <> "Bundler::BundlerError"
  AND c1.name <> "Bundler"
  AND c2.name <> "Bundler"

RETURN *
LIMIT 1
```


![Cylic dependency example](cyclic-dependencies.svg)

OK so now we're getting somewhere

You can see an interacting version of these results [here](http://portal.graphgist.org/graph_gist_candidates/3d5e8fe6-3e86-46d7-91e1-cccd612d5137#)

Great!

What does the source code look like?
Well let's include the `CallStack` nodes. So we can see the relevant chains of execution


```
MATCH (c1:Class)-[o:OWNS]->(m1:Method)
  -[con1:CONTAINS]->(cs1:CallSite)-[call1:CALLS]->(m2:Method)
  -[con2:CONTAINS]->(cs2:CallSite)-[call2:CALLS]->(m3:Method)
  <-[o2:OWNS]-(c1),
(c2:Class)-[o3:OWNS]->(m2),

(callstack:CallStack)-[:STEP]->(cs1),
(callstack:CallStack)-[:STEP]->(cs2)

WHERE c2.name <> c1.name
  AND c1.name <> "Bundler::BundlerError"
  AND c2.name <> "Bundler::BundlerError"
  AND c1.name <> "Bundler"
  AND c2.name <> "Bundler"

RETURN *
LIMIT 1
```


![Cylic dependency with call stack](cyclic-dependencies-with-call-stack.svg)

OK If we look at the step numbers we have step 533 and 534.
Woah! Way down the rabbit hole.

![Rabbit hole](The-rabbit-hole-natasha-bishop.jpg)

That means this is step 533 in just the application code (excluding libraries).
Imagine trying to debug your way into that.

OK so now we have the execution chains and the files and line numbers we can go and look at what's happening in the source code.


Within the Delfos repo:

```
NEO4J_PORT=8001 bin/console
```

```ruby
require "delfos/neo4j"

Delfos::Neo4j.execute_sync(<<-QUERY)
  MATCH (c1:Class)-[o:OWNS]->(m1:Method)
    -[con1:CONTAINS]->(cs1:CallSite)-[call1:CALLS]->(m2:Method)
    -[con2:CONTAINS]->(cs2:CallSite)-[call2:CALLS]->(m3:Method)
    <-[o2:OWNS]-(c1),
  (c2:Class)-[o3:OWNS]->(m2),

  (callstack:CallStack)-[:STEP]->(cs1),
  (callstack:CallStack)-[:STEP]->(cs2)

  WHERE c2.name <> c1.name
    AND c1.name <> "Bundler::BundlerError"
    AND c2.name <> "Bundler::BundlerError"
    AND c1.name <> "Bundler"
    AND c2.name <> "Bundler"

  RETURN *
  LIMIT 1
QUERY

=> [[{"name"=>"Bundler::Source::Git"}, {"name"=>"Bundler::StubSpecification"}, {}, {}, {"uuid"=>"c1b21cb9-e558-49f4-8f4c-4a7281c840bf"}, {}, {}, {"file"=>"lib/bundler/source/path.rb", "line_number"=>166}, {"file"=>"lib/bundler/stub_specification.rb", "line_number"=>23}, {"file"=>"lib/bundler/source/git.rb", "name"=>"load_spec_files", "line_number"=>200, "type"=>"InstanceMethod"}, {"file"=>"lib/bundler/stub_specification.rb", "name"=>"source=", "line_number"=>18, "type"=>"InstanceMethod"}, {"file"=>"lib/bundler/source/git.rb", "name"=>"extension_dir_name", "line_number"=>106, "type"=>"InstanceMethod"}, {}, {}, {}]]
```

OK so `RETURN *` might be a bit hard to parse.

Howabout:

```ruby
require "delfos/neo4j"

Delfos::Neo4j.execute_sync(<<-QUERY)
  MATCH (c1:Class)-[o:OWNS]->(m1:Method)
    -[con1:CONTAINS]->(cs1:CallSite)-[call1:CALLS]->(m2:Method)
    -[con2:CONTAINS]->(cs2:CallSite)-[call2:CALLS]->(m3:Method)
    <-[o2:OWNS]-(c1),
  (c2:Class)-[o3:OWNS]->(m2),

  (callstack:CallStack)-[:STEP]->(cs1),
  (callstack:CallStack)-[:STEP]->(cs2)

  WHERE c2.name <> c1.name
    AND c1.name <> "Bundler::BundlerError"
    AND c2.name <> "Bundler::BundlerError"
    AND c1.name <> "Bundler"
    AND c2.name <> "Bundler"

  RETURN cs1, cs2
  LIMIT 1
QUERY

=> [[{"file"=>"lib/bundler/source/path.rb", "line_number"=>166}, {"file"=>"lib/bundler/stub_specification.rb", "line_number"=>23}]]
```

Alright that's easier. Let's have a look at the source around line 166


```ruby
puts File.readlines("../bundler/lib/bundler/source/path.rb")[160..170].map.with_index{|l, i| "#{160+i+1}: #{l}" }
161:
162:         if File.directory?(expanded_path)
163:           # We sort depth-first since `<<` will override the earlier-found specs
164:           Dir["#{expanded_path}/#{@glob}"].sort_by {|p| -p.split(File::SEPARATOR).size }.each do |file|
165:             next unless spec = load_gemspec(file)
166:             spec.source = self
167:
168:             # Validation causes extension_dir to be calculated, which depends
169:             # on #source, so we validate here instead of load_gemspec
170:             validate_spec(spec)
171:             index << spec
```

OK, so we're setting `spec.source` to be self. Which might explain the circular dependency.

Just looking at 5 lines either side isn't great though. Can we see the whole method?


```ruby
require "delfos/neo4j"

Delfos::Neo4j.execute_sync(<<-QUERY)
  MATCH (c1:Class)-[o:OWNS]->(m1:Method)
    -[con1:CONTAINS]->(cs1:CallSite)-[call1:CALLS]->(m2:Method)
    -[con2:CONTAINS]->(cs2:CallSite)-[call2:CALLS]->(m3:Method)
    <-[o2:OWNS]-(c1),
  (c2:Class)-[o3:OWNS]->(m2),

  (callstack:CallStack)-[:STEP]->(cs1),
  (callstack:CallStack)-[:STEP]->(cs2)

  WHERE c2.name <> c1.name
    AND c1.name <> "Bundler::BundlerError"
    AND c2.name <> "Bundler::BundlerError"
    AND c1.name <> "Bundler"
    AND c2.name <> "Bundler"

  RETURN c1, m1, c2, m2
  LIMIT 1
QUERY

=> [[{"name"=>"Bundler::Source::Git"}, {"file"=>"lib/bundler/source/git.rb", "name"=>"load_spec_files", "line_number"=>200, "type"=>"InstanceMethod"}, 
{"name"=>"Bundler::StubSpecification"}, {"file"=>"lib/bundler/stub_specification.rb", "name"=>"source=", "line_number"=>18, "type"=>"InstanceMethod"}]]
```


OK So `Bundler::Source::Git#load_spec_files` calls `Bundler::StubSpecification#source=`

how about pry?


```ruby
require "pry"
binding.pry
[2] pry(main)> show-source Bundler::Source::Git#load_spec_files

From: /Users/markburns/.rbenv/versions/2.4.0/lib/ruby/gems/2.4.0/gems/bundler-1.15.1/lib/bundler/source/git.rb @ line 200:
Owner: Bundler::Source::Git
Visibility: public
Number of lines: 6

def load_spec_files
  super
rescue PathError => e
  Bundler.ui.trace e
  raise GitError, "#{self} is not yet checked out. Run `bundle install` first."
end

[3] pry(main)> show-source Bundler::StubSpecification#source=

From: /Users/markburns/.rbenv/versions/2.4.0/lib/ruby/gems/2.4.0/gems/bundler-1.15.1/lib/bundler/stub_specification.rb @ line 18:
Owner: Bundler::StubSpecification
Visibility: public
Number of lines: 8

def source=(source)
  super
  # Stub has no concept of source, which means that extension_dir may be wrong
  # This is the case for git-based gems. So, instead manually assign the extension dir
  return unless source.respond_to?(:extension_dir_name)
  path = File.join(stub.extensions_dir, source.extension_dir_name)
  stub.extension_dir = File.expand_path(path)
end
```

OK nice. So now wouldn't it be great to be able to step through any CallStack in the graph?

How many do we have?

```cypher
MATCH (c1:CallStack)
RETURN count(c1)
```

```
count(c1)
13782
```

Over 13,000 `CallStack`s to look at.

OK now my next project is to write a CallStack browser....


