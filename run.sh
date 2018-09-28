#!/bin/bash

export FLASK_APP=jtr
export FLASK_ENV=development
python -c "import jtr; jtr.db.create_all()"
flask run &
sleep 1
curl -X POST http://localhost:5000/add-ripper -d "label=1&id=1"
curl -X POST http://localhost:5000/add-ripper -d "label=2&id=2"
curl -X POST http://localhost:5000/add-ripper -d "label=3&id=3"
curl -X POST http://localhost:5000/add-ripper -d "label=4&id=4"
curl -X POST http://localhost:5000/add-ripper -d "label=5&id=5"
curl -X POST http://localhost:5000/add-ripper -d "label=6&id=6"
curl -X POST http://localhost:5000/add-ripper -d "label=7&id=7"
curl -X POST http://localhost:5000/add-ripper -d "label=8&id=8"
curl -X POST http://localhost:5000/add-ripper -d "label=9&id=9"
curl -X POST http://localhost:5000/add-ripper -d "label=10&id=10"
curl -X POST http://localhost:5000/add-ripper -d "label=11&id=11"
curl -X POST http://localhost:5000/add-ripper -d "label=12&id=12"
curl -X POST http://localhost:5000/add-ripper -d "label=13&id=13"
curl -X POST http://localhost:5000/add-ripper -d "label=14&id=14"
curl -X POST http://localhost:5000/add-ripper -d "label=15&id=15"
curl -X POST http://localhost:5000/add-ripper -d "label=16&id=16"
curl -X POST http://localhost:5000/add-ripper -d "label=17&id=17"
curl -X POST http://localhost:5000/add-ripper -d "label=18&id=18"
curl -X POST http://localhost:5000/add-ripper -d "label=19&id=19"

kill_and_quit() {
    pkill flask
    exit 0
}
trap kill_and_quit SIGINT

wait

