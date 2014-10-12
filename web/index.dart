import "dart:html";
import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "dart:web_gl" as GL;
import "dart:math" as Math;

import "package:vector_math/vector_math.dart";

class Canvas {
  static const int CANVAS_WIDTH = 512;
  static const int CANVAS_HEIGHT = 512;

  CanvasElement _canvas;
  CanvasElement _video_canvas;

  CanvasRenderingContext2D _video_canvas_context;

  GL.RenderingContext _gl;
  GL.Program _program;

  GL.Buffer _vbo_position;
  GL.Buffer _vbo_coord;
  GL.Buffer _ibo_indices;
  int _indices_length;

  GL.UniformLocation _u_mvp_matrix;
  GL.UniformLocation _u_texture;

  GL.Texture _video_texture;

  Quaternion _quaternion;
  Vector3 _look_from;

  int _a_position;
  int _a_texture_coord;

  VideoElement _video;

  static const String VS =
  """
  attribute vec3 position;
  attribute vec2 texture_coord;

  uniform mat4 mvp_matrix;

  varying vec2 v_texture_coord;

  void main(void){
      v_texture_coord = texture_coord;
      gl_Position   = mvp_matrix * vec4(position, 1.0);
  }
  """;

  static const String FS =
  """
  precision mediump float;

  uniform sampler2D texture;
  varying vec2 v_texture_coord;

  void main(void){
      vec4 color = texture2D(texture, v_texture_coord);
      gl_FragColor  = color;
  }
  """;

  static const String MOVIE_URI = "movie.mp4";
  static const int MOVIE_WIDTH = 854;
  static const int MOVIE_HEIGHT = 480;

  Canvas(String selector) {
    CanvasElement canvas = querySelector(selector);
    if (canvas == null) {
      throw(new Exception("Could not get element: ${this._canvas}"));
    }
    this._canvas = canvas;

    this._gl = canvas.getContext3d();
    if (this._gl == null) {
      throw(new Exception("Could not initialize WebGL context."));
    }

    var gl = this._gl;
    var vs = gl.createShader(GL.VERTEX_SHADER);
    gl.shaderSource(vs, Canvas.VS);
    gl.compileShader(vs);

    if(gl.getShaderParameter(vs, GL.COMPILE_STATUS) == null) {
      throw(new Exception("Could not compile shader\n${gl.getShaderInfoLog(vs)}"));
    }

    var fs = gl.createShader(GL.FRAGMENT_SHADER);
    gl.shaderSource(fs, Canvas.FS);
    gl.compileShader(fs);

    if(gl.getShaderParameter(fs, GL.COMPILE_STATUS) == null) {
      throw(new Exception("Could not compile shader\n${gl.getShaderInfoLog(fs)}"));
    }

    var program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);

    if(gl.getProgramParameter(program, GL.LINK_STATUS) == null) {
      throw(new Exception("Could not compile shader\n${gl.getProgramInfoLog(program)}"));
    }

    this._u_texture = gl.getUniformLocation(program, "texture");
    this._u_mvp_matrix = gl.getUniformLocation(program, "mvp_matrix");

    this._a_position = gl.getAttribLocation(program, "position");
    this._a_texture_coord = gl.getAttribLocation(program, "texture_coord");

    this._video_texture = gl.createTexture();
    gl.bindTexture(GL.TEXTURE_2D, this._video_texture);
    gl.pixelStorei(GL.UNPACK_FLIP_Y_WEBGL, 1);
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
    gl.bindTexture(GL.TEXTURE_2D, null);

    gl.useProgram(program);
    this._program = program;

    var video_canvas = new CanvasElement()
      ..width = CANVAS_WIDTH
      ..height = CANVAS_HEIGHT
    ;

    CanvasRenderingContext2D video_canvas_context = video_canvas.getContext("2d");

    this._video_canvas = video_canvas;
    this._video_canvas_context = video_canvas_context;

    var video = new VideoElement()
      ..width = MOVIE_WIDTH
      ..height = MOVIE_HEIGHT
      ..src = MOVIE_URI
      ..loop = true
    ;
    this._video = video;

    this._look_from = new Vector3(0.0, 0.0, 35.0);
    this._quaternion = new Quaternion.identity();

    Point p0 = null;
    this._canvas.onMouseDown.listen((MouseEvent event){
      event.preventDefault();

      p0 = event.client;
    });

    this._canvas.onMouseMove.listen((MouseEvent event){
      event.preventDefault();

      if(p0 != null) {
        Point p = event.client - p0;
        this._quaternion = (new Quaternion.identity() .. setEuler(p.x * 0.01, p.y * 0.01, 0.0)) * this._quaternion;
        p0 = event.client;
      }
    });

    this._canvas.onMouseUp.listen((MouseEvent event){
      event.preventDefault();

      p0 = null;
    });
  }

  Future<Stream<num>> start() {
    Completer<Stream<num>> completer = new Completer<Stream<num>>();
    Future<Stream<num>> future = completer.future;

    HttpRequest request = new HttpRequest();
    request.onLoad.listen((event){
      var gl = this._gl;
      gl.getExtension("OES_float_linear");
      this._video.play();

      Map teapot = JSON.decode(request.responseText);

      var vbo_position = gl.createBuffer();
      gl.bindBuffer(GL.ARRAY_BUFFER, vbo_position);
      gl.bufferDataTyped(GL.ARRAY_BUFFER, new Float32List.fromList(teapot["positions"] as List<double>), GL.STATIC_DRAW);
      this._vbo_position = vbo_position;

      var vbo_coord = gl.createBuffer();
      gl.bindBuffer(GL.ARRAY_BUFFER, vbo_coord);
      gl.bufferDataTyped(GL.ARRAY_BUFFER, new Float32List.fromList(teapot["coords"] as List<double>), GL.STATIC_DRAW);
      this._vbo_coord = vbo_coord;

      var ibo_indices = gl.createBuffer();
      var indices = teapot["indices"] as List<int>;
      gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, ibo_indices);
      gl.bufferDataTyped(GL.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(indices), GL.STATIC_DRAW);
      this._ibo_indices = ibo_indices;
      this._indices_length = indices.length;

      StreamController<num> controller = new StreamController<num>.broadcast();
      RequestAnimationFrameCallback render;
      render = (num ms) {
        window.requestAnimationFrame(render);
        controller.add(ms);
      };
      window.requestAnimationFrame(render);

      completer.complete(controller.stream);
    });
    request.open("GET", "teapot.json");
    request.send();

    return future;
  }

  void render(num ms) {
    var gl = this._gl;

    Matrix4 projection = new Matrix4.identity();
    setPerspectiveMatrix(projection, Math.PI * 60.0 / 180.0, this._canvas.width / this._canvas.height, 0.1, 1000.0);

    Matrix4 view = new Matrix4.identity();
    setViewMatrix(view, this._look_from, new Vector3(0.0, 0.0, 0.0), new Vector3(0.0, 1.0, 0.0));

    Matrix4 model = new Matrix4.identity();
    model.setRotation(this._quaternion.asRotationMatrix());

    Matrix4 mvp = projection * view * model;

    var ctx = this._video_canvas_context;
    int height = CANVAS_HEIGHT * MOVIE_HEIGHT ~/ MOVIE_WIDTH;
    int destY = (CANVAS_HEIGHT - height) ~/ 2;
    ctx.drawImageScaled(this._video, 0, destY, CANVAS_WIDTH, height);

    gl.bindTexture(GL.TEXTURE_2D, this._video_texture);
    gl.texImage2D(GL.TEXTURE_2D, 0, GL.RGBA, GL.RGBA, GL.UNSIGNED_BYTE, this._video_canvas);
    gl.bindTexture(GL.TEXTURE_2D, null);

    gl.activeTexture(GL.TEXTURE0);
    gl.enable(GL.DEPTH_TEST);
    gl.clearColor(0.5, 0.5, 0.5, 1.0);
    gl.clearDepth(1.0);
    gl.clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);

    gl.bindTexture(GL.TEXTURE_2D, this._video_texture);

    gl.uniform1i(this._u_texture, 0);
    gl.uniformMatrix4fv(this._u_mvp_matrix, false, mvp.storage);

    gl.bindBuffer(GL.ARRAY_BUFFER, this._vbo_position);
    gl.enableVertexAttribArray(this._a_position);
    gl.vertexAttribPointer(this._a_position, 3, GL.FLOAT, false, 0, 0);

    gl.bindBuffer(GL.ARRAY_BUFFER, this._vbo_coord);
    gl.enableVertexAttribArray(this._a_texture_coord);
    gl.vertexAttribPointer(this._a_texture_coord, 2, GL.FLOAT, false, 0, 0);

    gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, this._ibo_indices);
    gl.drawElements(GL.TRIANGLES, this._indices_length, GL.UNSIGNED_SHORT, 0);
  }
}

void main()
{
  var canvas = new Canvas("#canvas");
  canvas.start()
  .then((Stream<num> stream){
    stream.listen((num ms){
      canvas.render(ms);
    });
  });
}

