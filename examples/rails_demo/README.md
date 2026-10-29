# Rails webhook demo

This is a deliberately minimal Rails integration-test application. It sends
synthetic events to two local controllers, using an in-memory SQLite database.
The tests use the library's duplicate and reverse scenarios and post to actual
Rails endpoints. They assert that the naive controller fails the same credit
invariant that the second example passes for these specific sequential cases.
This is not production payment code and does not verify provider signatures,
model concurrency, make external requests, or guarantee exactly-once processing.

Run from this directory with Ruby 3.2+ and the dependencies in `Gemfile`:

```sh
bundle install
bundle exec ruby test/webhook_delivery_test.rb
```
