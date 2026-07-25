# Sky Typing Tutor

An attempt to use [sky](https://github.com/anzellai/sky/) to implement
the [typing tutor](https://github.com/roovo/typing-tutor) I built
using elm a while ago

## Requirments

```bash
# sky compiles to go
brew install go

# needed if building from source
brew install rust

# to buld from souce
git clone https://github.com/anzellai/sky
cd sky && cargo install --path rust/crates/sky --root ~/.local --locked
```

## Develpment

```bash
# run tests
./run-tests.sh

# run individual test file
sky test tests/ExerciseTests.sky

# build & run
sky build
./sky-out/app src/Main.sky   # path to file to use in exercise

# or just run
sky run
```
