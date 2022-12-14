// Programa en c++ para difuminar rostros en videos

#include <assert.h>
#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <time.h>

#include <cuda_runtime.h>
#include <opencv2/objdetect.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <iostream>

#define N (2048*2048)
#define THREADS_PER_BLOCK 512

using namespace std;
using namespace cv;

__global__ void Add(const float *A, const float *B, float *C, int numElements, int pixel_size)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;

    if (i < numElements)
    {
        if (i<=1){
            C[i] = A[i] + B[i];
        }else{
             C[i] = B[i] + pixel_size < A[i] ? pixel_size : A[i] - B[i];
        }
    }
}

void random_ints(int* a, int n){
    int i;
    for (i = 0; i < n; ++i)
    a[i] = rand();
}

// Function para detectar rostros
void detectAndDraw(Mat& img, CascadeClassifier& cascade,
    CascadeClassifier& nestedCascade, double scale, int threadsPerBlock);
string cascadeName, nestedCascadeName;

int main(int argc, char* argv[])
{

    // Clase VideoCapture para reproducir videos para los cuales se detectarán las caras
    VideoCapture capture;
    //Crea un objeto VideoWriter, aún no inicializado
    VideoWriter writer;
    Mat frame, image;
    string filename;
    int threadsPerBlock;
    // Clasificadores XML entrenados predefinidos con características faciales
    CascadeClassifier cascade, nestedCascade;
    double scale = 1;

    // Cargar clasificadores
    nestedCascade.load("/home/opencv/data/haarcascades/haarcascade_eye_tree_eyeglasses.xml");
    cascade.load("/home/opencv/data/haarcascades/haarcascade_frontalface_alt.xml");
    
       
    
    if (argc != 4) {
        cout << "Error en numero de parametros de entrada" << endl;
        exit(0);
    }
    else {
        // Ruta para el videos
        String nameIn = argv[1];
        String nameOut = argv[2];
        threadsPerBlock = stoi(argv[3]);
        String videoRouteIn = "/content/" + nameIn;
        String videoRouteExit = "/content/" + nameOut;
        capture.open(videoRouteIn);
        filename = videoRouteExit;// Nombre del video de salida
    }
    int total_frames = capture.get(cv::CAP_PROP_FRAME_COUNT);
    if (capture.isOpened())
    {
        // capturar fotogramas de vídeo y detectar rostros
        cout << "Deteccion de rostros iniciada" << endl;
        int frame_width = capture.get(cv::CAP_PROP_FRAME_WIDTH);
        int frame_height = capture.get(cv::CAP_PROP_FRAME_HEIGHT);
        Size frame_size(frame_width, frame_height);
        double fps = capture.get(CAP_PROP_FPS); //after open the capture obj
        int total_frames = capture.get(cv::CAP_PROP_FRAME_COUNT);

        //Define los fps de video de salida
        int FPS = fps; //Frames per second

        //Defina el códec de video por FOURCC, método de grabación, entero fourcc
        int fcc = VideoWriter::fourcc('X', 'V', 'I', 'D');
        //'X','V','I','D' códec de código abierto
        //'M','J','P','G' Vídeo JPEG en movimiento
        //'X','2','6','4' mplementación H.264 de código abierto (comprimido)

        //Inicializar el objeto VideoWriter
        writer = VideoWriter(filename, fcc, FPS, frame_size, true);
        while (1)
        {
            capture >> frame;
            if (frame.empty()){
                break;
            }
            Mat frame1 = frame.clone();
            detectAndDraw(frame1, cascade, nestedCascade, scale, threadsPerBlock);
            //Escribe el frame en el archivo de salida.
            writer.write(frame1);
        }
    }
    else
        cout << "Video no encontrado";
    //lanza el video de salida
    writer.release();
    return 0;
}

void detectAndDraw(Mat& img, CascadeClassifier& cascade,
    CascadeClassifier& nestedCascade,
    double scale, int threadsPerBlock)
{
    vector<Rect> faces, faces2;
    Mat gray, smallImg;

    cvtColor(img, gray, COLOR_BGR2GRAY); // Convierte a scala de grises
    double fx = 1 / scale;

    // Cambiar el tamaño de la imagen en escala de grises
    resize(gray, smallImg, Size(), fx, fx, INTER_LINEAR);
    equalizeHist(smallImg, smallImg);

    // Detecta caras de diferentes tamaños usando el clasificador en cascada 
    cascade.detectMultiScale(smallImg, faces, 1.1,
        2, 0 | CASCADE_SCALE_IMAGE, Size(30, 30));
    // Pixela las caras.
    for (size_t h = 0; h < faces.size(); h++)
    {
        Rect r = faces[h];
        Mat smallImgROI;
        vector<Rect> nestedObjects;
        
        int pixel_size = 16;
        Rect rect;
        for (int i = 0; i < r.width; i += pixel_size)
        {
            for (int j = 0; j < r.height; j += pixel_size)
            {
                cudaError_t err = cudaSuccess;

                // Print the vector length to be used, and compute its size
                int numElements = 4;
                size_t size = numElements * sizeof(float);

                // Allocate the host input vector A
                float *h_A = (float *)malloc(size);

                // Allocate the host input vector B
                float *h_B = (float *)malloc(size);

                // Allocate the host output vector C
                float *h_C = (float *)malloc(size);

                h_A[0] = r.x;
                h_B[0] = j;
                h_A[1] = r.y;
                h_B[1] = i;
                h_A[2] = r.height;
                h_B[2] = j;
                h_A[3] = r.width;
                h_B[3] = i;

                // Allocate the device input vector A
                float *d_A = NULL;
                err = cudaMalloc((void **)&d_A, size);

                float *d_B = NULL;
                err = cudaMalloc((void **)&d_B, size);

               
                float *d_C = NULL;
                err = cudaMalloc((void **)&d_C, size);

                err = cudaMemcpy(d_A, h_A, size, cudaMemcpyHostToDevice);

                err = cudaMemcpy(d_B, h_B, size, cudaMemcpyHostToDevice);

                
                int blocksPerGrid =(numElements + threadsPerBlock - 1) / threadsPerBlock;
                Add<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, d_C, numElements, pixel_size);
                err = cudaGetLastError();

                err = cudaMemcpy(h_C, d_C, size, cudaMemcpyDeviceToHost);
                rect.x = h_C[0];
                rect.y = h_C[1];
                rect.width = h_C[2];
                rect.height = h_C[3];
                
                // obtener el color promedio del area indicada
                Scalar color = mean(Mat(img, rect));

                // pintar el area indicada con el color obtenido
                rectangle(img, rect, color, cv::FILLED);
            }
        }

        if (nestedCascade.empty())
            continue;
        smallImgROI = smallImg(r);
    }

}
