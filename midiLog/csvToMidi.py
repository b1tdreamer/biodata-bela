import mido
import csv

mid = mido.MidiFile()
track = mido.MidiTrack()
mid.tracks.append(track)

with open('notas.csv', newline='') as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        note = int(row['note'].replace('d',''))
        velocity = int(row['velocity'].replace('d',''))
        channel = int(row['channel'].replace('d',''))
        msg_type = row.get('type', 'on')

        msg = mido.Message('note_on' if msg_type == 'on' else 'note_off', note=note, velocity=velocity, channel=channel, time=0)
        track.append(msg)

mid.save('salida.mid')