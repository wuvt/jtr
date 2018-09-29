import uuid
import datetime
from enum import Enum, auto

from jtr import db
from sqlalchemy.dialects.postgresql import UUID

class CDRipState(Enum):
    DONE = auto()
    IN_PROGRESS = auto()
    ERROR = auto()

class CDRip(db.Model):
    __tablename__ = 'cd_rip'

    def __init__(self, artist, album, label, stack, disc, barcode):
        self.artist = artist
        self.album = album
        self.label = label
        self.stack = stack
        self.disc = disc
        self.barcode = barcode
        self.state = CDRipState.IN_PROGRESS
        self.progress = 0
        self.uuid = uuid.uuid4()

    id = db.Column(db.Integer, primary_key=True)
    uuid = db.Column(UUID(as_uuid=True))
    created = db.Column(db.DateTime, default=datetime.datetime.utcnow)
    artist = db.Column(db.Unicode(255).with_variant(db.Unicode, 'postgresql'))
    album = db.Column(db.Unicode(255).with_variant(db.Unicode, 'postgresql'))
    label = db.Column(db.Unicode(255).with_variant(db.Unicode, 'postgresql'))
    stack = db.Column(db.Unicode(255).with_variant(db.Unicode, 'postgresql'))
    disc = db.Column(db.Unicode(255).with_variant(db.Unicode, 'postgresql'))
    barcode = db.Column(db.Integer, unique=True)
    state = db.Column(db.Enum(CDRipState))
    progress = db.Column(db.Integer)

class Ripper(db.Model):
    __tablename__ = 'ripper'

    def __init__(self, id_num=None, label=None):
        if id_num is not None:
            self.id = id_num
        if label is not None:
            self.label = label

    id = db.Column(db.Integer, primary_key=True)
    label = db.Column(db.String(10), unique=True, nullable=False)
    current_rip_id = db.Column(db.Integer, db.ForeignKey('cd_rip.id'))
    current_rip = db.relationship('CDRip', backref=db.backref('ripper', lazy='dynamic'))

