/*
    __  ____            __                 
   /  |/  (_)________  / /___  ______  ___ 
  / /|_/ / / ___/ __ \/ __/ / / / __ \/ _ \
 / /  / / / /__/ /_/ / /_/ /_/ / / / /  __/
/_/  /_/_/\___/\____/\__/\__,_/_/ /_/\___/

*/

/// Project MicoTune
/// Art Director Santiago Morilla
/// Sound Designer and NIME Joaku de Sotavento
/// Ascii and midilogs by b1tdreamer

/// Version 0.1 Samplers Manipulation and MIDI reading

/*

Primer version de synth granular para el bela controlada por biodata, genera polyfonias pero tienen un time out para
que paren los samplers despues de unos segundos

*/

s = Server.default;

// Configuración de Bela
s.options.numAnalogInChannels = 8;
s.options.numAnalogOutChannels = 8;
s.options.numDigitalChannels = 16;
s.options.blockSize = 16;
s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 2;

s.options.postln;

// Esperar a que el servidor arranque
s.waitForBoot {
    // ==== SETUP ====

    // Generar timestamp para el archivo
    var timestamp = Date.getDate.stamp.replace(":", "-");
    var logPath = "/root/Bela/projects/Biodata/midiLog_" ++ timestamp ++ ".csv";
    ~logFile = File(logPath, "w");

    if(~logFile.isOpen) {
        "Archivo CSV abierto: %\n".format(logPath).postln;
        ~logFile.write("timestamp,note,velocity,channel,type\n");
    } {
        "No se pudo abrir archivo CSV.".postln;
    };

    // Cargar el buffer de audio
    ~buf = Buffer.read(s, "C_futujaraShort.wav");

    // Definir el sintetizador
    SynthDef(\midiSamplePlayer, {
        |out=0, bufnum=0, amp=0.5, rate=1.0, start=0.0, end=0.1, gate=1, reverse=0.0, timeoutSecs=5|
        var sig, numFrames, startPos, endPos, pointer, env;
        var kStart, kEnd, phasorRate, resetTrig, resetPos;
        var playStart, playEnd, autoRelease, finalGate;

        numFrames = BufFrames.kr(bufnum);
        kStart = Lag.kr(start, 0.02).clip(0.0, 1.0);
        kEnd = Lag.kr(end, 0.02).clip(0.0, 1.0 - kStart);

        startPos = kStart * numFrames;
        endPos = (kStart + kEnd) * numFrames;

        playStart = Select.kr(reverse > 0.5, [startPos, endPos]);
        playEnd = Select.kr(reverse > 0.5, [endPos, startPos]);
        resetPos = playStart;

        phasorRate = BufRateScale.kr(bufnum) * rate * Select.kr(reverse > 0.5, [-1, 1]);

        autoRelease = Done.kr(Line.kr(0, 0, timeoutSecs));
        finalGate = gate * (1 - autoRelease);

        env = EnvGen.kr(Env.asr(0.01, 1, 0.1), finalGate, doneAction: 2);

        pointer = Phasor.ar(trigger: 0, rate: phasorRate, start: playStart, end: playEnd, resetPos: resetPos);

        resetTrig = Select.kr(reverse > 0.5, [
            (pointer >= endPos),
            (pointer <= startPos)
        ]).lag(0.001);

        pointer = Phasor.ar(
            trigger: Trig.kr(resetTrig, 0.001),
            rate: phasorRate,
            start: playStart,
            end: playEnd,
            resetPos: resetPos
        );

        sig = BufRd.ar(2, bufnum, pointer, interpolation: 2);
        sig = sig * amp * env;
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    // Crear el synth silencioso inicial
    ~player = Synth(\midiSamplePlayer, [\bufnum, ~buf.bufnum, \amp, 0, \rate, 1, \start, 0, \end, 1]);
    ~player.free;

    // Inicializar MIDI
    MIDIClient.init;
    MIDIIn.connectAll;

    ~voices = IdentityDictionary.new;
    ~rate = 1.0;

    // Control de pitch vía CC
    MIDIdef.cc(\rateControl, { |val, num, chan|
        ~rate = val.linlin(0, 127, -2.0, 2.0);
    }, ccNum: 80);

    // Note ON
    MIDIdef.noteOn(\sampleNoteOn, { |vel, note, chan, src|
        var startPos = note.linlin(36, 96, 0.0, 1.0).clip(0.0, 1.0);
	    var amp = vel.linlin(1, 127, 0.1, 1.0);
	    var now = Date.getDate.stamp.replace(":", "-");
	    var synth = Synth(\midiSamplePlayer, [
	        \bufnum, ~buf,
	        \start, startPos,
	        \amp, amp,
	        \rate, ~rate,
	        \end, 0.05,
	        \reverse, 0.0,
	        \gate, 1
	    ]);
        
        ~voices[note] = synth;
	
	    // Seguridad para escribir en CSV
	    if(~logFile.notNil and: { ~logFile.isOpen }) {
	        ("Registrando nota: % % %\n".format(note, vel, chan)).postln;
	        ~logFile.write(timestamp ++ "," ++ note.asString ++ "," ++ vel.asString ++ "," ++ chan.asString ++ ",on\n");
	        ~logFile.flush;  // importante
	    } {
	        "No se pudo escribir en archivo".postln;
	    };
    });

    // Note OFF
    MIDIdef.noteOff(\sampleNoteOff, { |vel, note, chan, src|
	    var timestamp = Date.getDate.stamp.replace(":", "-");
	    var synth = ~voices[note];
	    ~logFile.write(timestamp ++ "," ++ note.asString ++ "," ++ vel.asString ++ "," ++ chan.asString ++ ",off\n");
	    
	    if(synth.notNil and: { synth.isPlaying }) {
	        synth.set(\gate, 0);
	        ~voices.removeAt(note);
	    } {
	        ~voices.removeAt(note);
	    };
	});
	
	//// Crear la rutina para hacer un "flush" del archivo cada minuto
	Routine({
	    inf.do { |i|
	        // Espera 60 segundos
	        60.wait;
	
	        // Hacer un "flush" del archivo CSV
	        ~logFile.flush;
	        "CSV file flushed.".postln;
	    };
	}).play;
    
};

// Cerrar archivo y salir al apagar el servidor
ServerQuit.add({
    if(~logFile.notNil and: { ~logFile.isOpen }) {
        ~logFile.close;
        "Archivo CSV cerrado.".postln;
    };
    0.exit;
});
