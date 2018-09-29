from flask import render_template, request, abort
from sqlalchemy import exc

from jtr import db, app
from jtr.models import CDRipState, CDRip, Ripper

def main_page(error=None):
    rippers = Ripper.query.order_by(Ripper.id).all()
    return render_template('ripper.html', rippers=rippers, error=error)

@app.route('/', methods=['GET', 'POST'])
def display():
    if request.method == 'GET':
        return main_page()
    elif request.method == 'POST':
        # First we'll validate the form
        if (request.form.get('id', None) is None or
                request.form.get('artist', None) is None or
                request.form.get('album', None) is None or
                request.form.get('label', None) is None or
                request.form.get('stack', None) is None or
                request.form.get('disc', None) is None or
                request.form.get('barcode', None) is None or
                request.form['id'].strip() == "" or
                request.form['artist'].strip() == "" or
                request.form['album'].strip() == "" or
                request.form['label'].strip() == "" or
                request.form['stack'].strip() == "" or
                request.form['disc'].strip() == "" or
                request.form['barcode'].strip() == "" ):
            rippers = Ripper.query.order_by(Ripper.id).all()
            return main_page(error="You must fill in all fields")
        # Let's do a little more validation on barcode
        id_num = request.form['id'].strip()
        artist = request.form['artist'].strip()
        album = request.form['album'].strip()
        label = request.form['label'].strip()
        stack = request.form['stack'].strip()
        disc = request.form['disc'].strip()
        barcode = request.form['barcode'].strip()

        try:
            id_num = int(id_num)
        except ValueError:
            return main_page(error="Ripper is not valid, are you screwing with the site?")

        try:
            barcode = int(barcode)
        except ValueError:
            return main_page(error="Barcode is not valid! Please enter it by scanning.")

        rip = CDRip(artist, album, label, stack, disc, barcode)
        db.session.add(rip)
        try:
            db.session.flush()
        except exc.IntegrityError:
            db.session.rollback()
            return main_page(error="Barcode already exists in system.")

        ripper = Ripper.query.get(id_num)
        ripper.current_rip = rip
        # Need to test duplicate barcodes here)
        db.session.commit()
        return main_page()


@app.route('/add-ripper', methods=['POST'])
def add_ripper():
    ripper = Ripper(id_num=int(request.form['id']), label=request.form['label'])
    try:
        db.session.add(ripper)
        db.session.commit()
        return "Success"
    except:
        return "Fail"

# curl http://localhost:5000/api/status/1
# curl -X PUT -d "state=IN_PROGRESS&progress=99" http://localhost:5000/api/status/1
# curl -X PUT -d "state=DONE" http://localhost:5000/api/status/1
# curl -X PUT -d "state=ERROR" http://localhost:5000/api/status/1
@app.route('/api/status/<int:ripper_id>', methods=['GET', 'PUT'])
def ripper_status(ripper_id):
    if request.method == 'GET':
        ripper = Ripper.query.get_or_404(ripper_id)
        if ripper.current_rip is None:
            return "None"
        else:
            return str(ripper.current_rip.uuid)
    if request.method == 'PUT':
        # I expect a progress number and a state which is one of "IN_PROGRESS",
        # "DONE", "ERROR"
        # Let's sanitize the input a bit
        if request.form.get('state', None) is None or \
                request.form['state'].strip() == "":
            abort(400)

        state = request.form['state'].strip()
        try:
            state = CDRipState.__members__[state]
        except:
            abort(400)

        # This means we're updating the progress of the rip
        if state == CDRipState.IN_PROGRESS:
            if request.form.get('progress', None) is None or \
                    request.form['progress'].strip() == "":
                abort(400)
            # Let's make it an int now
            progress = request.form['progress'].strip()
            try:
                progress = int(progress)
            except ValueError:
                abort(400)
            # Okay we got everything we need, let's update
            ripper = Ripper.query.get_or_404(ripper_id)
            if ripper.current_rip is None:
                abort(404)
            # We may want to ensure this is between 0 and 100 inclusive
            ripper.current_rip.progress = progress
            db.session.commit()

            return "Success"
        else:
            # This means we're done or erroring
            ripper = Ripper.query.get_or_404(ripper_id)
            if ripper.current_rip is None:
                abort(404)
            # Let's sanity check the state
            if ripper.current_rip.state != CDRipState.IN_PROGRESS:
                abort(500)
            # Set this to submitted state
            ripper.current_rip.state = state
            ripper.current_rip = None
            db.session.commit()
            return "Success"
