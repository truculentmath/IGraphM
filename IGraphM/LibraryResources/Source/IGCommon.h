/*
 * Copyright (c) 2018 Szabolcs Horvát.
 *
 * See the file LICENSE.txt for copying permission.
 */

#ifndef IGCOMMON_H
#define IGCOMMON_H

extern "C" { // workaround for igraph_version() C++ compatibility bug in igraph <= 0.7.1
#include <igraph/igraph.h>
}

#include "mlstream.h"
#include "LTemplate.h"

#include <algorithm>
#include <string>
#include <sstream>
#include <type_traits>


static_assert(std::is_same<double, igraph_real_t>::value, "IGraphM assumes igraph_real_t to be double.");
static_assert(sizeof(igraph_integer_t) == 4, "IGraphM assumes igraph_integer_t to be 32-bit.");
static_assert(std::is_same<int, igraph_bool_t>::value, "IGraphM assumes igraph_bool_t to be int.");
// See mlstream extractors, which are defined for integer types of particular widths.

inline igraph_vector_t igVectorView(mma::RealTensorRef t) {
    static double dummy = 0.0; // work around igraph not liking zero-length vectors will NULL pointers
    igraph_vector_t vec;
    mint len = t.length();
    igraph_vector_view(&vec, len == 0 ? &dummy : t.data(), len);
    return vec;
}


// RAII for igraph_vector_t
class igVector {
    bool moved;

public:
    igraph_vector_t vec;

    igVector() : moved(false) { igraph_vector_init(&vec, 0); }
    igVector(igVector &&source) noexcept : moved(false) { vec = source.vec; source.moved = true; }
    igVector(const igraph_vector_t *source) : moved(false) { igraph_vector_copy(&vec, source); }
    explicit igVector(long len) : moved(false) { igraph_vector_init(&vec, len); }

    igVector(const igVector &igv) : igVector() { igraph_vector_copy(&vec, &igv.vec); }

    igVector & operator = (const igVector &igv) {
        igraph_vector_copy(&vec, &igv.vec);
        return *this;
    }

    ~igVector() { if (!moved) igraph_vector_destroy(&vec); }

    long length() const { return vec.end - vec.stor_begin; }

    igraph_real_t *begin() { return vec.stor_begin; }
    igraph_real_t *end() { return vec.end; }

    const igraph_real_t *begin() const { return vec.stor_begin; }
    const igraph_real_t *end() const { return vec.end; }

    igraph_real_t & operator [] (size_t i) { return begin()[i]; }
    const igraph_real_t & operator [] (size_t i) const { return begin()[i]; }

    void clear() { igraph_vector_clear(&vec); }
    void resize(long newsize) { igraph_vector_resize(&vec, newsize); }

    void copyFromMTensor(mma::RealTensorRef t) {
        igraph_vector_t from = igVectorView(t);
        igraph_vector_update(&vec, &from);
    }

    mma::RealTensorRef makeMTensor() const { return mma::makeVector<double>(length(), begin()); }
};


// RAII for graph_vector_bool_t
class igBoolVector {

    // avoid accidental implicit copy
    igBoolVector(const igBoolVector &) = delete;
    igBoolVector & operator = (const igBoolVector &) = delete;

public:

    igraph_vector_bool_t vec;

    igBoolVector(long sz) { igraph_vector_bool_init(&vec, sz); }
    igBoolVector() { igraph_vector_bool_init(&vec, 0); }
    ~igBoolVector() { igraph_vector_bool_destroy(&vec); }

    long length() const { return vec.end - vec.stor_begin; }

    igraph_bool_t *begin() { return vec.stor_begin; }
    igraph_bool_t *end() { return vec.end; }

    const igraph_bool_t *begin() const { return vec.stor_begin; }
    const igraph_bool_t *end() const { return vec.end; }

    void clear() { igraph_vector_bool_clear(&vec); }
    void resize(long newsize) { igraph_vector_bool_resize(&vec, newsize); }

    mma::IntTensorRef makeMTensor() const { return mma::makeVector<mint>(length(), begin()); }
};


// RAII for igraph_vector_int_t
// note that igraph_integer_t and mint may not be the same type
class igIntVector {

    // avoid accidental implicit copy
    igIntVector(const igIntVector &) = delete;
    igIntVector & operator = (const igIntVector &) = delete;

public:
    igraph_vector_int_t vec;

    igIntVector() { igraph_vector_int_init(&vec, 0); }
    ~igIntVector() { igraph_vector_int_destroy(&vec); }

    long length() const { return vec.end - vec.stor_begin; }

    igraph_integer_t *begin() { return vec.stor_begin; }
    igraph_integer_t *end() { return vec.end; }

    const igraph_integer_t *begin() const { return vec.stor_begin; }
    const igraph_integer_t *end() const { return vec.end; }

    void clear() { igraph_vector_int_clear(&vec); }
    void resize(long newsize) { igraph_vector_int_resize(&vec, newsize); }

    void copyFromMTensor(mma::IntTensorRef t) {
        resize(t.length());
        std::copy(t.begin(), t.end(), begin());
    }

    mma::IntTensorRef makeMTensor() const { return mma::makeVector<mint>(length(), begin()); }
};


// RAII for igraph_maxtrix_t
struct igMatrix {
    igraph_matrix_t mat;

    igMatrix() { igraph_matrix_init(&mat, 0, 0); }
    ~igMatrix() { igraph_matrix_destroy(&mat); }

    long length() const { return mat.data.end - mat.data.stor_begin; }
    long nrow() const { return mat.nrow; }
    long ncol() const { return mat.ncol; }

    igraph_real_t *begin() { return mat.data.stor_begin; }
    igraph_real_t *end() { return mat.data.end; }

    const igraph_real_t *begin() const { return mat.data.stor_begin; }
    const igraph_real_t *end() const { return mat.data.end; }

    void copyFromMTensor(mma::RealMatrixRef t) {
        igraph_vector_t from = igVectorView(t);
        igraph_vector_update(&mat.data, &from);
        // Mathematica uses row-major storage, igraph uses column-major storage
        // thus we need to reverse the row/column counts, then transpose
        mat.nrow = t.cols();
        mat.ncol = t.rows();
        igraph_matrix_transpose(&mat);
    }

    mma::RealMatrixRef makeMTensor() const { return mma::makeMatrixTransposed<double>(mat.nrow, mat.ncol, begin()); }
};


// RAII for igraph_vector_ptr_t containing igraph_vector_t
template<typename ElemType, void DestroyElem(ElemType *)>
class igPtrVector {

    void destroy_items() {
        for (void **ptr = list.stor_begin; ptr < list.end; ++ptr)
            DestroyElem(reinterpret_cast<ElemType *>(*ptr));
    }

public:
    igraph_vector_ptr_t list;

    igPtrVector() {
        igraph_vector_ptr_init(&list, 0);
    }
    ~igPtrVector() {
        // we destroy items manually ...
        destroy_items();

        // ... and avoid calling any items destructors that may have been set
        igraph_vector_ptr_set_item_destructor(&list, nullptr);
        igraph_vector_ptr_free_all(&list);
        igraph_vector_ptr_destroy(&list);
    }

    void clear() {
        // this mirrors igraph_vector_ptr_clear(), but does not call
        // any item desctructors automatically to avoid double-free
        destroy_items();
        list.end = list.stor_begin;
    }

    long length() const { return igraph_vector_ptr_size(&list); }

    void push(igraph_vector_t *vec) { igraph_vector_ptr_push_back(&list, vec); }

    const ElemType *operator [] (long i) const { return static_cast<const ElemType *>(list.stor_begin[i]); }
};


typedef igPtrVector<igraph_vector_t, igraph_vector_destroy> igList;
typedef igPtrVector<igraph_t, igraph_destroy> igGraphList;


// extend mlstream with igraph-specific types

inline mlStream & operator << (mlStream &ml, const igraph_vector_t &vec) {
    if (! MLPutReal64List(ml.link(), vec.stor_begin, vec.end - vec.stor_begin))
        ml.error("cannot return vector");
    return ml;
}


inline mlStream & operator << (mlStream &ml, const igVector &vec) { return ml << vec.vec; }


inline mlStream & operator << (mlStream &ml, const igList &list) {
    long len = list.length();
    if (! MLPutFunction(ml.link(), "List", len))
        ml.error("cannot return vector list");
    for (int i=0; i < len; ++i)
        ml << *static_cast<igraph_vector_t *>(VECTOR(list.list)[i]);
    return ml;
}


inline mlStream & operator << (mlStream &ml, const igMatrix &mat) {
    int dims[2];
    dims[0] = mat.ncol();
    dims[1] = mat.nrow();
    int ok =
            MLPutFunction(ml.link(), "Transpose", 1) &&
            MLPutReal64Array(ml.link(), mat.begin(), dims, nullptr, 2);
    if (! ok)
        ml.error("cannot return matrix");
    return ml;
}


inline mlStream & operator >> (mlStream &ml, igList &list) {
    list.clear();
    int len;
    if (! MLTestHead(ml.link(), "List", &len))
        ml.error("List of lists expected");
    igraph_vector_ptr_resize(&list.list, len);
    for (int i=0; i < len; ++i) {
        igraph_vector_t *vec = static_cast<igraph_vector_t *>(igraph_malloc(sizeof(igraph_vector_t)));
        double *data;
        int listlen;
        if (! MLGetReal64List(ml.link(), &data, &listlen))
            ml.error("Real64List expected in list of lists");
        igraph_vector_init(vec, listlen);
        std::copy(data, data+listlen, vec->stor_begin);
        MLReleaseReal64List(ml.link(), data, listlen);
        VECTOR(list.list)[i] = vec;
    }
    return ml;
}


inline mlStream & operator >> (mlStream &ml, igVector &vec) {
    double *data;
    int length;
    if (! MLGetReal64List(ml.link(), &data, &length))
        ml.error("Real64List expected");
    vec.resize(length);
    std::copy(data, data+length, vec.begin());
    MLReleaseReal64List(ml.link(), data, length);
    return ml;
}


inline mlStream & operator >> (mlStream &ml, igMatrix &mat) {
    double *data;
    int *dims;
    char **heads;
    int depth;
    if (! MLGetReal64Array(ml.link(), &data, &dims, &heads, &depth))
        ml.error("Real64 matrix expected");
    if (depth != 2)
        ml.error("Real64 matrix expected, depth doesn't match");

    int length = 1;
    for (int i=0; i < depth; ++i)
        length *= dims[i];
    igraph_vector_resize(&mat.mat.data, length);
    std::copy(data, data+length, mat.begin());
    mat.mat.nrow = dims[1];
    mat.mat.ncol = dims[0];
    MLReleaseReal64Array(ml.link(), data, dims, heads, depth);
    return ml;
}

inline mlStream & operator >> (mlStream &ml, igIntVector &vec) {
    int *data;
    int length;
    // igraph_integer_t is an int, so we try to use the corresponding MathLink type: Integer32
    if (! MLGetInteger32List(ml.link(), &data, &length))
        ml.error("Integer32List expected");
    vec.resize(length);
    std::copy(data, data+length, vec.begin());
    MLReleaseInteger32List(ml.link(), data, length);
    return ml;
}


inline mlStream & operator >> (mlStream &ml, igBoolVector &vec) {
    int *data;
    int length;
    // igraph_bool_t is an int, so we try to use the corresponding MathLink type: Integer32
    if (! MLGetInteger32List(ml.link(), &data, &length))
        ml.error("Integer32List expected");
    vec.resize(length);
    std::copy(data, data+length, vec.begin());
    MLReleaseInteger32List(ml.link(), data, length);
    return ml;
}


// check igraph's error codes and abort if necessary
inline void igCheck(int err) {
    if (! err) return;
    std::ostringstream msg;
    msg << "igraph returned with error: " << igraph_strerror(err);
    throw mma::LibraryError(msg.str());
}


#endif // IGCOMMON_H

